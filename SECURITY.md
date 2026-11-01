# Security

Search evaluates JMESPath syntax without executing Ruby query text.
Input adapters and custom functions execute caller-supplied Ruby code.
They are trusted application extensions, not a sandbox boundary.

Use finite JSON numbers and avoid cyclic input when comparing or serializing entire values.
Set a smaller `max_depth` for applications that need a lower nesting limit.
Bound request sizes and runtime resources at the application boundary.

Run `bundle exec rake audit` to refresh the dependency advisory database and check the lockfile.
A failed database update fails the audit.

Report vulnerabilities privately to [leonid@svyatov.com](mailto:leonid@svyatov.com).
Leonid Svyatov will respond within 7 days.
Include the affected version, a minimal reproduction, and the security impact.
Do not post credentials or private application data in public reports.
