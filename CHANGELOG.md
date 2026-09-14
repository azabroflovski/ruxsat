# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
The project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Before 1.0, minor versions may contain breaking changes, and they are marked
**Breaking**.

## [Unreleased]

## [0.1.0] - 2026-09-14

### Added

- `use Ruxsat` with `allow/2,3` rules, compiled into the policy module.
- Rule options `role:`, `owner:` and `if:`.
- Generated `can?/3`, `authorize/3`, `authorize!/3`, `explain/3` and `rules/0`.
- `Ruxsat.ForbiddenError`, raised by `authorize!/3`.
- Compile-time validation of rules.

[Unreleased]: https://github.com/azabroflovski/ruxsat/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/azabroflovski/ruxsat/releases/tag/v0.1.0
