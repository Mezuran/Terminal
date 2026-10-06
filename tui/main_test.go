package main

import (
	"strings"
	"testing"
)

func TestOptionalToolsStartUnchecked(t *testing.T) {
	options := defaultOptions()
	if len(options) != 14 {
		t.Fatalf("expected 14 optional tools, got %d", len(options))
	}
	for _, item := range options {
		if item.selected {
			t.Errorf("%s should not be selected by default", item.id)
		}
	}
}

func TestAgentDescriptionsExplainAutomaticCharmAppearance(t *testing.T) {
	want := map[string]string{
		"codex":    "Charm syntax theme applied automatically",
		"opencode": "Charm UI theme applied automatically",
		"claude":   "Charm Dark UI theme applied automatically",
		"cursor":   "Charm dark hint",
	}
	for _, item := range defaultOptions() {
		if phrase, ok := want[item.id]; ok && !strings.Contains(item.description, phrase) {
			t.Errorf("%s description %q should explain its Charm appearance: %q", item.id, item.description, phrase)
		}
	}
}

func TestSelectedIDsKeepOptionOrder(t *testing.T) {
	m := model{options: defaultOptions()}
	for i := range m.options {
		m.options[i].compatible = true
	}
	m.options[1].selected = true  // Go
	m.options[7].selected = true  // PHP
	m.options[13].selected = true // Cursor

	got := m.selectedIDs()
	want := []string{"go", "php", "cursor"}
	if len(got) != len(want) {
		t.Fatalf("got %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("got %v, want %v", got, want)
		}
	}
}

func TestSelectedIDsExcludeIncompatibleOptions(t *testing.T) {
	m := model{options: defaultOptions()}
	for i := range m.options {
		m.options[i].selected = true
	}
	m.options[0].compatible = true

	got := m.selectedIDs()
	if len(got) != 1 || got[0] != "rust" {
		t.Fatalf("incompatible selections should be excluded, got %v", got)
	}
}

func TestCompatibilityDetectsSupportedLinuxAndMacDevices(t *testing.T) {
	for _, host := range []deviceInfo{
		{os: "linux", arch: "amd64", libc: "glibc", packageManager: "apt-get", hasSudo: true},
		{os: "darwin", arch: "arm64", hasBrew: true},
	} {
		for _, item := range optionsForDevice(host) {
			if !item.compatible {
				t.Errorf("%s should be available on %s/%s: %s", item.id, host.os, host.arch, item.reason)
			}
		}
	}
}

func TestCompatibilityDisablesMissingSystemPackageSupport(t *testing.T) {
	host := deviceInfo{os: "linux", arch: "amd64", libc: "glibc", binaries: map[string]bool{}}
	options := optionsForDevice(host)
	for _, item := range options {
		switch item.id {
		case "php", "composer", "clang", "gcc":
			if item.compatible || item.reason == "" {
				t.Errorf("%s should explain why its package is unavailable", item.id)
			}
		default:
			if !item.compatible {
				t.Errorf("%s should remain available on Linux: %s", item.id, item.reason)
			}
		}
	}
}

func TestCompatibilityDisablesUnsupportedPlatformAndMacGCC(t *testing.T) {
	windows := optionsForDevice(deviceInfo{os: "windows", arch: "amd64"})
	for _, item := range windows {
		switch item.id {
		case "rust", "go", "bun", "nodejs", "uv", "python", "codex", "opencode", "claude", "cursor":
			if !item.compatible {
				t.Errorf("%s should be offered on native Windows: %s", item.id, item.reason)
			}
		default:
			if item.compatible {
				t.Errorf("%s should require a detected Windows prerequisite", item.id)
			}
		}
	}
	for _, item := range optionsForDevice(deviceInfo{os: "windows", arch: "arm64"}) {
		if item.id == "cursor" && !item.compatible {
			t.Fatalf("Cursor should be offered on supported Windows arm64: %s", item.reason)
		}
	}
	for _, item := range optionsForDevice(deviceInfo{os: "darwin", arch: "arm64"}) {
		if item.id == "gcc" && item.compatible {
			t.Fatal("GNU GCC should be disabled on macOS without Homebrew")
		}
	}
}

func TestTermuxCompatibilityUsesOnlyVerifiedPackageAndBinaryPaths(t *testing.T) {
	host := deviceInfo{os: "termux", arch: "arm64", packageManager: "pkg", binaries: map[string]bool{}}
	if reason := coreIncompatibilityReason(host); reason != "" {
		t.Fatalf("Termux arm64 should support the pkg-based core: %s", reason)
	}
	wantEnabled := map[string]bool{
		"rust": true, "go": true, "nodejs": true, "python": true, "php": true, "composer": true, "clang": true,
	}
	for _, item := range optionsForDevice(host) {
		if item.compatible != wantEnabled[item.id] {
			t.Errorf("Termux compatibility for %s = %t (%s), want %t", item.id, item.compatible, item.reason, wantEnabled[item.id])
		}
		if item.id == "go" && !strings.Contains(item.description, "temporarily to build Pop") {
			t.Errorf("Termux Go description should explain its temporary core-build dependency: %q", item.description)
		}
	}
}

func TestTermuxRequiresPkgAndSupportedArchitecture(t *testing.T) {
	for _, host := range []deviceInfo{
		{os: "termux", arch: "arm64"},
		{os: "termux", arch: "amd64", packageManager: "pkg"},
	} {
		if reason := coreIncompatibilityReason(host); reason == "" {
			t.Errorf("expected Termux host %+v to explain unavailable core", host)
		}
	}
}

func TestNativeWindowsArm64ReportsOnlyMissingCoreBinaries(t *testing.T) {
	host := deviceInfo{os: "windows", arch: "arm64"}
	if reason := coreIncompatibilityReason(host); reason != "" {
		t.Fatalf("Windows arm64 should support a partial core install: %s", reason)
	}
	warnings := coreWarningsForDevice(host)
	if strings.Join(warnings, ",") != "lsd (no verified Windows arm64 release),Glow (no verified Windows arm64 release),Pop (no verified Windows arm64 release)" {
		t.Fatalf("unexpected Windows arm64 core warnings: %v", warnings)
	}
}

func TestNativeWindowsComposerRequiresPHP(t *testing.T) {
	host := deviceInfo{os: "windows", arch: "amd64", binaries: map[string]bool{"composer": true}}
	for _, item := range optionsForDevice(host) {
		if item.id == "composer" && item.compatible {
			t.Fatal("Composer should not be offered without PHP, even if a composer command is present")
		}
	}
	host.binaries["php"] = true
	for _, item := range optionsForDevice(host) {
		if item.id == "composer" && !item.compatible {
			t.Fatalf("Composer should be offered when PHP is available: %s", item.reason)
		}
	}
}

func TestTermuxDetectionDoesNotTreatWSLAsAndroid(t *testing.T) {
	if !isTermuxEnvironment("android", "", "") || !isTermuxEnvironment("linux", "/data/data/com.termux/files/usr", "") || !isTermuxEnvironment("linux", "", "0.118") {
		t.Fatal("expected Android and Termux environment markers to be recognized")
	}
	if isTermuxEnvironment("linux", "/usr", "") || isTermuxEnvironment("windows", "", "") {
		t.Fatal("ordinary Linux/WSL and Windows must not be misdetected as Termux")
	}
}

func TestMuslLinuxDisablesOptionsBecauseCoreInstallNeedsGlibc(t *testing.T) {
	host := deviceInfo{os: "linux", arch: "amd64", libc: "musl"}
	host.coreReason = coreIncompatibilityReason(host)
	if host.coreReason == "" {
		t.Fatal("musl Linux should explain why the core install is unavailable")
	}
	for _, item := range optionsForDevice(host) {
		if item.compatible {
			t.Errorf("%s should be disabled when core setup cannot run", item.id)
		}
	}
}

func TestUnknownLinuxLibcDoesNotAssumeCompatibility(t *testing.T) {
	host := deviceInfo{os: "linux", arch: "arm64", libc: "unknown"}
	if reason := coreIncompatibilityReason(host); reason == "" {
		t.Fatal("unknown Linux libc should not be assumed to support the core install")
	}
}

func TestTrimLineTruncatesLongInstallerOutput(t *testing.T) {
	got := trimLine("line\x1b[31m with carriage\rreturn", 15)
	if len([]rune(got)) > 15 {
		t.Fatalf("trimLine returned %d runes, want at most 15: %q", len([]rune(got)), got)
	}
	if got == "line\x1b[31m with carriage\rreturn" {
		t.Fatal("trimLine did not sanitize terminal control characters")
	}
}
