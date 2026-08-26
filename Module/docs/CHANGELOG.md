# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.2.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.2]

### Added

- `ConvertTo-NinjaOneHtml`: `-MaxTopFiles`, `-MaxTopFolders`, `-ShowAllResults`, `-FooterSuffix` parameters
- Per-drive ranked **Top Files** and **Top Folders** tables (full width)
- Two-column **Cleanup** + **File Types** layout per drive
- `New-HtmlRankedStack` helper for stacked ranked tables in NinjaOne WYSIWYG

### Changed

- NinjaOne dark mode: `stat-desc` for muted text; explicit dark text on info-card titles/descriptions
- Status badges use inline background and foreground colors (WYSIWYG-safe contrast)
- Footer shows UltraTree version from the module manifest; optional `-FooterSuffix` for caller branding
- Removed duplicate `$script:Config.Version`; version comes from `UltraTree.psd1` only

## [0.2.0]

### Added

- Initial release.
