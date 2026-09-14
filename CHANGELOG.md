# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
The project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Before 1.0, minor versions may contain breaking changes, and they are marked
**Breaking**.

## [Unreleased]

## [0.2.0] - 2026-09-14

### Added

- `where:` rule option. It checks that resource fields equal literal values,
  e.g. `allow :read, Post, where: [published: true]`. `explain/3` reports a
  failed check as `:where_mismatch`.
- Generated `filter/3`. It describes which records a subject may access, as
  `:all`, `:none` or `{:any, sets}`. The result is plain data with no Ecto
  dependency, and the README includes a recipe for Ecto queries. Rules that use
  `if:` cannot be turned into data, so `filter/3` raises for them.

## [0.1.0] - 2026-09-14

### Added

- `use Ruxsat` with `allow/2,3` rules, compiled into the policy module.
- Rule options `role:`, `owner:` and `if:`.
- Generated `can?/3`, `authorize/3`, `authorize!/3`, `explain/3` and `rules/0`.
- `Ruxsat.ForbiddenError`, raised by `authorize!/3`.
- Compile-time validation of rules.

[Unreleased]: https://github.com/azabroflovski/ruxsat/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/azabroflovski/ruxsat/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/azabroflovski/ruxsat/releases/tag/v0.1.0
