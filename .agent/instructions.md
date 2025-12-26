# AI Agent Instructions

These instructions define the mandatory workflow for AI agents working on this project.

## Workflow: Fix Lints & Tests

When addressing issues or making changes, follow this strict order of operations:

1.  **Single Pass Efficiency**: Whenever possible, apply fixes for both linting and testing issues in a single pass to minimize iterations.
2.  **Linting First**: Always resolve linting errors (e.g., `flake8`, `mypy`) *before* attempting to fix functional tests. A clean codebase is the foundation.
3.  **Run Tests**: Execute the test suite to verify changes.
4.  **Coverage Verification**:
    -   Generate the coverage badge immediately after running tests.
    -   **Mandatory**: Ensure code coverage is **at least 90%**.
    -   If coverage is below 90%, add necessary tests before considering the task complete.

## Cross-Platform Compatibility

-   **Mocks**: key mocks MUST be compatible with both **Windows** and **Linux** environments.
    -   *Example*: When mocking `os` or `ctypes`, ensure you handle platform-specific attributes (like `os.add_dll_directory` which is Windows-specific) gracefully, usually by using `create=True` in mocks or checking `sys.platform`.
    -   Do not assume a specific OS environment for the test runner.

## Quick Commands
-   **Run Tests & Generate Badge**: `COVERAGE=1 ./tests/run_suite.sh`
