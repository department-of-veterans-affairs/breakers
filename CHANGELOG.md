# Changelog

## [1.0] - 2025-03-24
### Added
- Support matching by service name (#40)

## [1.0.1] - 2025-06-05
### Added
- Allows forced outages to persist until explicitly ended, using `bundle exec rake breakers:end_forced_outage service="VAOS"`, for example.