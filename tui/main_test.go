package main

import "testing"

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

func TestSelectedIDsKeepOptionOrder(t *testing.T) {
	m := initialModel()
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

func TestTrimLineTruncatesLongInstallerOutput(t *testing.T) {
	got := trimLine("line\x1b[31m with carriage\rreturn", 15)
	if len([]rune(got)) > 15 {
		t.Fatalf("trimLine returned %d runes, want at most 15: %q", len([]rune(got)), got)
	}
	if got == "line\x1b[31m with carriage\rreturn" {
		t.Fatal("trimLine did not sanitize terminal control characters")
	}
}
