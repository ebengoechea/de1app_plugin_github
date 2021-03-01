# Changelog - "GitHub Plugins" Decent DE1app plugin

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [1.01] - [Unreleased]
### Changed
- Fix sizes and positions of the plugins listbox and the "Browse release" and "What's new?" buttons so they don't 
collide with other widgets depending on font used (e.g. on DSx).

## [1.00] - 2021-02-28
### Added
- Initial release: Install or update plugins from their GitHub repositories, using either the repos taken from the
plugins.tdb file (updated from GitHub on first listbox fill in a session), or the github_repo namespace variable in 
installed plugins. For updates, makes a backup of the previous version and allows to restore it automatically.