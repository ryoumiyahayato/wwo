# vNext validation

Run all vNext validation from the repository root with:

```text
python -B tools/run_vnext_validation.py --root . --godot <godot-executable>
```

The runner normalizes the repository root, resolves the Godot executable, performs one headless editor import/script scan, then recursively discovers every file under `tests/vnext/` whose name ends with `_test.gd`. Tests are executed in dictionary order by repository-relative path.

Validation fails on a nonzero Godot exit code or when captured stdout/stderr contains `SCRIPT ERROR`, `Parse Error`, `Failed to load script`, `Could not resolve class`, `Could not find type`, `Assertion failed`, or a nonzero `failures` count. Each test must also emit a summary containing a nonzero checks count and `0 failures`.

New vNext test scripts must live under `tests/vnext/` and end with `_test.gd`. No registry or workflow entry is required for an individual test.

GitHub Actions uses the same command through `.github/workflows/vnext-runtime.yml` after installing Godot 4.6.3. The workflow also runs the Python self-tests for the runner.

Business modules must not copy or introduce their own Godot test runner. vNext test execution belongs to `tools/run_vnext_validation.py`.
