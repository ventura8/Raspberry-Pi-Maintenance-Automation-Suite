# AI Instructions: Raspberry Pi Maintenance & Automation Suite

Technical guidance for AI agents and developers working on this project.

> **AI Agents**: Please refer to [.agent/instructions.md]((.agent/instructions.md)) for specific workflows regarding linting, testing, and mocks.

## Coverage Requirement

> **Mandatory**: Maintain a minimum of **90% code coverage**.

- Badge updates are done **locally** using `COVERAGE=1 ./tests/run_suite.sh`
- Always commit `assets/coverage.svg` after making code changes

## Samsung SSD Firmware Updates

The `update_samsung_ssd.sh` script dynamically scrapes Samsung's official firmware page to find the latest firmware for detected NVMe SSDs. Supported models include 9100/990/980/970/960/950 series.

**Key Implementation Notes:**
- Primary method: `fwupdmgr` (LVFS)
- Fallback: Scrapes `https://semiconductor.samsung.com/consumer-storage/support/tools/`
- Extracts `fumagician` from ISO's `initrd` to apply updates
- No hardcoded firmware versions - always fetches latest

## Automatic Dependency Installation

Both `update_pi_firmware.sh` and `update_samsung_ssd.sh` include a `check_and_install_dependencies` function. This ensures that required tools (e.g., `fwupd`, `nvme-cli`, `rpi-eeprom-update`, `ssmtp`) are installed automatically based on the detected hardware and OS environment.

## Self-Update Mechanism

The suite includes a self-healing capability (`scripts/update_self.sh`) that ensures installations stay current.

*   **Version Tracking**: The installer tracks the **GitHub Release Tag** (e.g., `v1.0.0`) in `.version`.
*   **Update Logic**:
    1.  `update_self.sh` checks the GitHub API (`releases/latest`).
    2.  Compares the remote Tag with the local `.version` file.
    3.  If a mismatch is found, it downloads and executes the `install.sh` from that specific release tag.
*   **Notifications**: The script sends email reports for:
    *   **Success**: "The suite has been updated to version $TAG."
    *   **Up-to-Date**: "System is up to date (Version $TAG)."
    *   **Failure**: Includes specific error reason (e.g., API failure, Download error).
*   **Testing**: This feature is tested via `tests/component_tests_self_update.bats`, mocking the Releases API.

## Documentation Index

- [Project Overview & Directory Structure](docs/project_overview.md)
- [Script Logic & Functionality](docs/script_logic.md)
- [Development & Standards](docs/development_standards.md)

