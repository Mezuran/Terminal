package main

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"

	"github.com/charmbracelet/bubbles/progress"
	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

var (
	cream  = lipgloss.Color("#fffdf5")
	muted  = lipgloss.Color("#a49bab")
	violet = lipgloss.Color("#9671ff")
	mint   = lipgloss.Color("#00ffb2")
	pink   = lipgloss.Color("#ff6daa")
	lime   = lipgloss.Color("#ecfd65")

	titleStyle = lipgloss.NewStyle().Bold(true).Foreground(cream).Background(violet).Padding(0, 2)
	mutedStyle = lipgloss.NewStyle().Foreground(muted)
	keyStyle   = lipgloss.NewStyle().Bold(true).Foreground(mint)
	checked    = lipgloss.NewStyle().Bold(true).Foreground(mint)
	unchecked  = lipgloss.NewStyle().Foreground(muted)
	nameStyle  = lipgloss.NewStyle().Bold(true).Foreground(cream)
	statusGood = lipgloss.NewStyle().Bold(true).Foreground(mint)
	statusBad  = lipgloss.NewStyle().Bold(true).Foreground(pink)
	ansiCSI    = regexp.MustCompile("\\x1b\\[[0-?]*[ -/]*[@-~]")
)

type option struct {
	id          string
	name        string
	description string
	selected    bool
	compatible  bool
	reason      string
}

func defaultOptions() []option {
	return []option{
		{id: "rust", name: "Rust", description: "Stable toolchain via rustup"},
		{id: "go", name: "Go", description: "Latest stable Go release"},
		{id: "bun", name: "Bun", description: "Latest stable JavaScript runtime"},
		{id: "nodejs", name: "Node.js LTS", description: "Latest production LTS release"},
		{id: "uv", name: "uv", description: "Fast Python package/project manager"},
		{id: "python", name: "Python", description: "Latest stable Python via uv"},
		{id: "composer", name: "Composer", description: "PHP dependency manager (adds PHP if needed)"},
		{id: "php", name: "PHP", description: "Latest stable version available for this OS"},
		{id: "clang", name: "Clang", description: "LLVM compiler from your OS package channel"},
		{id: "gcc", name: "GCC", description: "GNU compiler from your OS package channel"},
		{id: "codex", name: "OpenAI Codex", description: "Stable CLI; Charm syntax theme applied automatically"},
		{id: "opencode", name: "OpenCode", description: "OpenCode TUI; Charm UI theme applied automatically"},
		{id: "claude", name: "Claude Code", description: "Stable CLI; Charm Dark UI theme applied automatically"},
		{id: "cursor", name: "Cursor CLI", description: "Agent CLI; Charm dark hint (Cursor controls accents)"},
	}
}

type deviceInfo struct {
	os             string
	arch           string
	libc           string
	coreReason     string
	coreWarnings   []string
	packageManager string
	hasBrew        bool
	hasSudo        bool
	binaries       map[string]bool
}

func detectDevice() deviceInfo {
	device := deviceInfo{
		os:       runtime.GOOS,
		arch:     runtime.GOARCH,
		hasBrew:  commandExists("brew"),
		hasSudo:  commandExists("sudo"),
		binaries: make(map[string]bool),
	}
	if isTermuxEnvironment(runtime.GOOS, os.Getenv("PREFIX"), os.Getenv("TERMUX_VERSION")) {
		device.os = "termux"
	}
	if device.os == "linux" {
		device.libc = detectLinuxLibc()
	}
	for _, name := range []string{"php", "clang", "gcc", "composer", "lsd", "glow", "pop"} {
		device.binaries[name] = commandExists(name)
	}
	if device.os == "termux" {
		if commandExists("pkg") {
			device.packageManager = "pkg"
		}
	} else if device.os == "linux" {
		for _, manager := range []string{"apt-get", "dnf", "pacman"} {
			if commandExists(manager) {
				device.packageManager = manager
				break
			}
		}
	}
	device.coreReason = coreIncompatibilityReason(device)
	device.coreWarnings = coreWarningsForDevice(device)
	return device
}

func isTermuxEnvironment(runtimeOS, prefix, version string) bool {
	return runtimeOS == "android" || version != "" || strings.Contains(prefix, "/com.termux/")
}

func detectLinuxLibc() string {
	for _, pattern := range []string{
		"/lib/ld-musl-*.so.1",
		"/lib64/ld-musl-*.so.1",
		"/usr/lib/ld-musl-*.so.1",
	} {
		if matches, _ := filepath.Glob(pattern); len(matches) > 0 {
			return "musl"
		}
	}
	if _, err := os.Stat("/etc/alpine-release"); err == nil {
		return "musl"
	}
	if output, err := exec.Command("getconf", "GNU_LIBC_VERSION").Output(); err == nil &&
		strings.HasPrefix(strings.TrimSpace(string(output)), "glibc ") {
		return "glibc"
	}
	for _, pattern := range []string{
		"/lib/ld-linux*.so*",
		"/lib64/ld-linux*.so*",
		"/usr/lib/ld-linux*.so*",
	} {
		if matches, _ := filepath.Glob(pattern); len(matches) > 0 {
			return "glibc"
		}
	}
	return "unknown"
}

func commandExists(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}

func optionsForDevice(device deviceInfo) []option {
	options := defaultOptions()
	if device.os == "termux" {
		for i := range options {
			if options[i].id == "go" {
				options[i].description = "Termux package; also required temporarily to build Pop"
			}
		}
	}
	if device.coreReason == "" {
		device.coreReason = coreIncompatibilityReason(device)
	}
	for i := range options {
		options[i].reason = incompatibilityReason(options[i].id, device)
		options[i].compatible = options[i].reason == ""
	}
	return options
}

func coreIncompatibilityReason(device deviceInfo) string {
	supportedArch := device.arch == "amd64" || device.arch == "arm64"
	switch device.os {
	case "termux":
		if device.arch != "arm64" {
			return fmt.Sprintf("Termux core packages are supported only on Android arm64 (detected %s)", device.arch)
		}
		if device.packageManager != "pkg" {
			return "Termux package manager 'pkg' was not detected"
		}
		return ""
	case "windows":
		if supportedArch {
			return ""
		}
		return fmt.Sprintf("core setup does not support windows/%s", device.arch)
	case "linux", "darwin":
		if !supportedArch {
			return fmt.Sprintf("core setup does not support %s/%s", device.os, device.arch)
		}
	default:
		return fmt.Sprintf("core setup does not support %s/%s", device.os, device.arch)
	}
	if device.os == "linux" && device.libc != "glibc" {
		if device.libc == "musl" {
			return "core binary releases require glibc; musl/Alpine is not supported"
		}
		return "could not confirm glibc support for this Linux device"
	}
	return ""
}

func coreWarningsForDevice(device deviceInfo) []string {
	if device.os == "windows" && device.arch == "arm64" {
		var warnings []string
		for _, tool := range []struct{ id, name string }{{"lsd", "lsd"}, {"glow", "Glow"}, {"pop", "Pop"}} {
			if !device.binaries[tool.id] {
				warnings = append(warnings, tool.name+" (no verified Windows arm64 release)")
			}
		}
		return warnings
	}
	return nil
}

func incompatibilityReason(id string, device deviceInfo) string {
	if device.coreReason != "" {
		return device.coreReason
	}
	if device.os == "termux" {
		return termuxIncompatibilityReason(id, device)
	}
	if device.os == "windows" {
		return windowsIncompatibilityReason(id, device)
	}
	if (device.os != "linux" && device.os != "darwin") ||
		(device.arch != "amd64" && device.arch != "arm64") {
		return fmt.Sprintf("not supported on %s/%s", device.os, device.arch)
	}

	canInstallPackage := device.hasBrew && device.os == "darwin"
	if device.os == "linux" && device.packageManager != "" && device.hasSudo {
		canInstallPackage = true
	}
	switch id {
	case "php":
		if !device.binaries["php"] && !canInstallPackage {
			return packageUnavailableReason(device)
		}
	case "composer":
		if !device.binaries["php"] && !canInstallPackage {
			return "requires PHP; no supported package installer is available"
		}
	case "clang":
		if !device.binaries["clang"] && !canInstallPackage {
			return packageUnavailableReason(device)
		}
	case "gcc":
		if device.os == "darwin" && !device.hasBrew {
			return "GNU GCC on macOS requires Homebrew"
		}
		if device.os == "linux" && !device.binaries["gcc"] && !canInstallPackage {
			return packageUnavailableReason(device)
		}
	}
	return ""
}

func termuxIncompatibilityReason(id string, device deviceInfo) string {
	switch id {
	case "rust", "go", "nodejs", "python", "php", "clang":
		return ""
	case "composer":
		if !device.binaries["php"] && device.packageManager != "pkg" {
			return "requires PHP from the Termux pkg repository"
		}
		return ""
	case "gcc":
		return "Termux provides Clang, not GNU GCC"
	case "bun":
		return "Bun does not publish a supported Android/Termux build"
	case "uv":
		return "uv does not publish a supported Android/Termux build"
	case "codex", "opencode", "claude", "cursor":
		return "this CLI does not publish a supported Android/Termux build"
	default:
		return "not supported in Termux"
	}
}

func windowsIncompatibilityReason(id string, device deviceInfo) string {
	switch id {
	case "rust", "go", "bun", "nodejs", "uv", "python", "codex", "opencode", "claude":
		return ""
	case "cursor":
		if device.arch == "amd64" || device.arch == "arm64" {
			return ""
		}
		return fmt.Sprintf("Cursor CLI does not support Windows %s", device.arch)
	case "php":
		if device.binaries["php"] {
			return ""
		}
		return "requires an existing PHP installation; automatic Windows PHP installation is not configured"
	case "composer":
		if device.binaries["php"] {
			return ""
		}
		return "requires PHP; install PHP first or add php.exe to PATH"
	case "clang":
		if device.binaries["clang"] {
			return ""
		}
		return "requires an existing LLVM/Clang installation on Windows"
	case "gcc":
		if device.binaries["gcc"] {
			return ""
		}
		return "requires an existing GCC/MinGW installation on Windows"
	default:
		return "not supported on Windows"
	}
}

func packageUnavailableReason(device deviceInfo) string {
	if device.os == "darwin" {
		return "requires Homebrew or an existing system compiler"
	}
	if device.packageManager == "" {
		return "requires a supported system package manager"
	}
	if !device.hasSudo {
		return "requires sudo to install the system package"
	}
	return "no supported system package installer is available"
}

type model struct {
	options       []option
	device        deviceInfo
	cursor        int
	width         int
	stage         string
	status        string
	logs          []string
	progress      progress.Model
	spinner       spinner.Model
	selected      []string
	processDone   bool
	processErr    error
	privilegeErr  error
	checkingSudo  bool
	commandCancel context.CancelFunc
}

type logMessage string
type processDoneMessage struct{ err error }
type sudoResultMessage struct{ err error }
type childStartedMessage struct{ cancel context.CancelFunc }

var activeProgram *tea.Program

func initialModel() model {
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = lipgloss.NewStyle().Foreground(violet)
	p := progress.New(progress.WithGradient("#00ffb2", "#9671ff"))
	device := detectDevice()
	device.coreReason = coreIncompatibilityReason(device)
	return model{
		options:  optionsForDevice(device),
		device:   device,
		stage:    "select",
		status:   "Choose optional tools. Core terminal setup is always included.",
		progress: p,
		spinner:  s,
	}
}

func (m model) Init() tea.Cmd { return nil }

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.progress.Width = max(20, min(54, msg.Width-10))
	case spinner.TickMsg:
		var cmd tea.Cmd
		m.spinner, cmd = m.spinner.Update(msg)
		return m, cmd
	case progress.FrameMsg:
		updated, cmd := m.progress.Update(msg)
		m.progress = updated.(progress.Model)
		return m, cmd
	case logMessage:
		line := strings.TrimSpace(string(msg))
		if strings.HasPrefix(line, "@@TERMINAL_PROGRESS\t") {
			fields := strings.SplitN(line, "\t", 4)
			if len(fields) == 4 {
				current, _ := strconv.Atoi(fields[1])
				total, _ := strconv.Atoi(fields[2])
				if total > 0 {
					m.status = fields[3]
					percent := float64(current) / float64(total)
					cmd := m.progress.SetPercent(percent)
					return m, cmd
				}
			}
			return m, nil
		}
		if line != "" {
			m.logs = append(m.logs, trimLine(line, max(48, min(110, m.width-8))))
			if len(m.logs) > 6 {
				m.logs = m.logs[len(m.logs)-6:]
			}
		}
		return m, nil
	case processDoneMessage:
		m.processDone = true
		m.processErr = msg.err
		m.stage = "done"
		if msg.err != nil {
			m.status = "Setup finished with an error. Review the output below."
		} else {
			m.status = "Your Charm terminal setup is ready."
		}
		return m, nil
	case sudoResultMessage:
		m.checkingSudo = false
		if msg.err != nil {
			m.privilegeErr = msg.err
			m.status = "Administrator approval was not granted; choose Run again or quit."
			return m, nil
		}
		m.privilegeErr = nil
		m.stage = "running"
		m.status = "Preparing your selected stable tools…"
		return m, tea.Batch(m.spinner.Tick, m.runInstaller())
	case childStartedMessage:
		m.commandCancel = msg.cancel
		return m, nil
	case tea.KeyMsg:
		if m.stage == "select" {
			switch msg.String() {
			case "ctrl+c", "q":
				return m, tea.Quit
			case "up", "k":
				if m.cursor > 0 {
					m.cursor--
				}
			case "down", "j":
				if m.cursor < len(m.options)-1 {
					m.cursor++
				}
			case " ":
				if m.options[m.cursor].compatible {
					m.options[m.cursor].selected = !m.options[m.cursor].selected
				}
			case "a":
				for i := range m.options {
					m.options[i].selected = m.options[i].compatible
				}
			case "n":
				for i := range m.options {
					m.options[i].selected = false
				}
			case "enter":
				if m.device.coreReason != "" {
					m.status = "This device cannot run the core Terminal install; press q to exit."
					return m, nil
				}
				m.selected = m.selectedIDs()
				if m.needsSudo() {
					m.checkingSudo = true
					m.status = "Selected system packages need administrator approval."
					cmd := exec.Command("sudo", "-v")
					return m, tea.ExecProcess(cmd, func(err error) tea.Msg { return sudoResultMessage{err: err} })
				}
				m.stage = "running"
				m.status = "Preparing your selected stable tools…"
				return m, tea.Batch(m.spinner.Tick, m.runInstaller())
			}
		} else if m.stage == "done" {
			switch msg.String() {
			case "q", "enter", "esc", "ctrl+c":
				return m, tea.Quit
			}
		} else if msg.String() == "ctrl+c" && m.commandCancel != nil {
			m.commandCancel()
			m.status = "Stopping installer…"
		}
	}
	return m, nil
}

func (m model) View() string {
	if m.width == 0 {
		return "\n  Starting Terminal…"
	}
	var b strings.Builder
	b.WriteString("\n")
	b.WriteString(titleStyle.Render(" ✦  TERMINAL  "))
	b.WriteString("\n\n")
	if m.stage == "select" {
		b.WriteString(lipgloss.NewStyle().Bold(true).Foreground(cream).Render("Choose your toolkit"))
		b.WriteString("\n")
		b.WriteString(mutedStyle.Render(fmt.Sprintf("Device: %s/%s · incompatible tools are disabled.", m.device.os, m.device.arch)))
		b.WriteString("\n")
		if m.device.coreReason != "" {
			b.WriteString(statusBad.Render("Core setup unavailable: ") + mutedStyle.Render(m.device.coreReason))
		} else {
			b.WriteString(mutedStyle.Render("Core setup is included; optional tools start unchecked."))
			if len(m.device.coreWarnings) > 0 {
				b.WriteString("\n" + statusBad.Render("Core items unavailable: ") + mutedStyle.Render(strings.Join(m.device.coreWarnings, ", ")))
			}
		}
		b.WriteString("\n\n")
		for i, item := range m.options {
			pointer := "  "
			if i == m.cursor {
				pointer = lipgloss.NewStyle().Foreground(violet).Bold(true).Render("› ")
			}
			box := unchecked.Render("○")
			name := nameStyle.Render(item.name)
			description := item.description
			if !item.compatible {
				box = lipgloss.NewStyle().Foreground(muted).Render("–")
				name = mutedStyle.Render(item.name)
				description = "Unavailable: " + item.reason
			} else if item.selected {
				box = checked.Render("●")
			}
			desc := mutedStyle.Render(description)
			b.WriteString(fmt.Sprintf("%s%s  %-18s %s\n", pointer, box, name, desc))
		}
		b.WriteString("\n")
		instructions := mutedStyle.Render("↑/↓ move  ") + keyStyle.Render("space") + mutedStyle.Render(" toggle  ") + keyStyle.Render("a") + mutedStyle.Render(" all  ") + keyStyle.Render("n") + mutedStyle.Render(" none  ")
		if m.device.coreReason == "" {
			instructions += keyStyle.Render("enter") + mutedStyle.Render(" install  ")
		}
		b.WriteString(instructions + keyStyle.Render("q") + mutedStyle.Render(" quit"))
		if m.checkingSudo || m.privilegeErr != nil {
			b.WriteString("\n\n" + lipgloss.NewStyle().Foreground(lime).Render(m.status))
		}
		return b.String()
	}

	if m.stage == "running" {
		b.WriteString(m.spinner.View() + " " + lipgloss.NewStyle().Bold(true).Foreground(cream).Render(m.status) + "\n\n")
		b.WriteString(m.progress.View() + "\n\n")
		for _, line := range m.logs {
			b.WriteString(mutedStyle.Render("  "+line) + "\n")
		}
		b.WriteString("\n" + mutedStyle.Render("ctrl+c to cancel"))
		return b.String()
	}

	if m.processErr == nil {
		b.WriteString(statusGood.Render("✓  ") + lipgloss.NewStyle().Bold(true).Foreground(cream).Render(m.status) + "\n\n")
	} else {
		b.WriteString(statusBad.Render("✗  ") + lipgloss.NewStyle().Bold(true).Foreground(cream).Render(m.status) + "\n\n")
	}
	for _, line := range m.logs {
		b.WriteString(mutedStyle.Render("  "+line) + "\n")
	}
	b.WriteString("\n" + mutedStyle.Render("enter or q to close"))
	return b.String()
}

func (m model) selectedIDs() []string {
	ids := make([]string, 0, len(m.options))
	for _, item := range m.options {
		if item.selected && item.compatible {
			ids = append(ids, item.id)
		}
	}
	return ids
}

func (m model) needsSudo() bool {
	if m.device.os != "linux" || os.Getenv("TERMINAL_SKIP_SUDO_PREFLIGHT") == "1" {
		return false
	}
	_, aptErr := exec.LookPath("apt-get")
	_, dnfErr := exec.LookPath("dnf")
	_, pacmanErr := exec.LookPath("pacman")
	if aptErr != nil && dnfErr != nil && pacmanErr != nil {
		return false
	}
	for _, id := range m.selected {
		switch id {
		case "php", "clang", "gcc":
			if _, err := exec.LookPath(id); err != nil {
				return true
			}
		case "composer":
			if _, err := exec.LookPath("php"); err != nil {
				return true
			}
		}
	}
	return false
}

func (m model) runInstaller() tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithCancel(context.Background())
		var cmd *exec.Cmd
		if m.device.os == "windows" {
			powershell := "powershell.exe"
			if commandExists("pwsh") {
				powershell = "pwsh"
			}
			cmd = exec.CommandContext(ctx, powershell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", os.Args[1], "-RunSelection", "-RunSelected", strings.Join(m.selected, ","))
		} else {
			cmd = exec.CommandContext(ctx, "bash", os.Args[1], "--run-selected", strings.Join(m.selected, ","))
		}
		configureChildCommand(cmd)
		reader, writer, err := os.Pipe()
		if err != nil {
			cancel()
			return processDoneMessage{err: err}
		}
		cmd.Stdout = writer
		cmd.Stderr = writer
		if err := cmd.Start(); err != nil {
			_ = reader.Close()
			_ = writer.Close()
			cancel()
			return processDoneMessage{err: err}
		}
		_ = writer.Close()
		stop := func() {
			stopChildCommand(cmd)
			cancel()
		}
		go func() {
			defer reader.Close()
			scanner := bufio.NewScanner(reader)
			scanner.Buffer(make([]byte, 2048), 1024*1024)
			for scanner.Scan() {
				if activeProgram != nil {
					activeProgram.Send(logMessage(scanner.Text()))
				}
			}
		}()
		if activeProgram != nil {
			activeProgram.Send(childStartedMessage{cancel: stop})
		}
		err = cmd.Wait()
		cancel()
		return processDoneMessage{err: err}
	}
}

func (m model) execute() error {
	p := tea.NewProgram(m, tea.WithAltScreen())
	activeProgram = p
	final, err := p.Run()
	if err != nil {
		return err
	}
	if result, ok := final.(model); ok {
		return result.processErr
	}
	return nil
}

func trimLine(line string, limit int) string {
	line = ansiCSI.ReplaceAllString(line, "")
	line = strings.ReplaceAll(line, "\r", " ")
	line = strings.TrimSpace(line)
	runes := []rune(line)
	if len(runes) <= limit {
		return line
	}
	return string(runes[:max(0, limit-1)]) + "…"
}

func main() {
	if len(os.Args) < 2 || strings.TrimSpace(os.Args[1]) == "" {
		fmt.Fprintln(os.Stderr, "usage: terminal-tui /path/to/install.sh-or-install.ps1")
		os.Exit(2)
	}
	if _, err := os.Stat(os.Args[1]); err != nil {
		fmt.Fprintln(os.Stderr, "installer script not found:", err)
		os.Exit(2)
	}
	if runtime.GOOS != "windows" {
		tty, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
		if err != nil {
			fmt.Fprintln(os.Stderr, "interactive terminal required; use the installer with --no-ui for non-interactive setup")
			os.Exit(2)
		}
		_ = tty.Close()
	}
	if err := initialModel().execute(); err != nil {
		if err != io.EOF {
			fmt.Fprintln(os.Stderr, "terminal setup failed:", err)
		}
		os.Exit(1)
	}
}
