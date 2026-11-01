# Ruby implementation comparison

The comparison covers the latest published versions found on November 1, 2026.
[RubyGems search](https://rubygems.org/api/v1/search.json?query=jmespath) and the upstream repositories identify these implementations:

| Gem | Version | Upstream | API used |
| --- | --- | --- | --- |
| jmespath-ruby | 0.1.0 checkout | [svyatov/jmespath-ruby](https://github.com/svyatov/jmespath-ruby) | `JMESPath.search`, `JMESPath.compile` |
| jmespath | 1.6.2 | [jmespath/jmespath.rb](https://github.com/jmespath/jmespath.rb) | `JMESPath.search`, persistent `JMESPath::Runtime` |
| burtpath | 1.1.2 | [burtcorp/burtpath](https://github.com/burtcorp/burtpath) | `JMESPath.search`, persistent `JMESPath::Runtime` |
| jamespath | 0.5.1 | [lsegal/jamespath](https://github.com/lsegal/jamespath) | `Jamespath.search`, `Jamespath.compile` |
| jmespath-jruby | 1.0.0.pre0 | [burtcorp/jmespath-jruby](https://github.com/burtcorp/jmespath-jruby) | `JmesPath#compile`, compiled query reuse |

The gem named `jmespath.rb` is an empty name-protection package, not the official implementation.
The official implementation uses the gem name `jmespath`.
`stack_master_json_parameter_store` consumes JMESPath rather than implementing it.
The mruby project has no RubyGems release in this search and targets a different Ruby runtime.

Package checksums and exclusions are recorded in the [source manifest](../../benchmark/results/comparison-sources.json).
This project's library source is revision `609c178dfe3be49e13c64ae1b49790570c9fec37`; each report also fingerprints the measured library files.

## MRI results

The following results use MRI 4.0.9 without YJIT.
Each speedup is the geometric mean of competitor time divided by this library's time, using only workloads both implementations evaluate correctly.
Each workload's time is the median of its five samples before ratios are calculated.
Each workload contributes equally to the mean.
A value above 1 favors this library; a value below 1 favors the competitor.

| Implementation | Correct search workloads | Public-search speedup | Search speedup range | Reuse speedup |
| --- | ---: | ---: | ---: | ---: |
| **jmespath-ruby 0.1.0** | **✅ 18/18** | **1.00x** | **Baseline** | **1.00x** |
| jmespath 1.6.2 | ✅ 18/18 | 7.97x | 1.35x to 78.48x | 4.35x |
| BurtPath 1.1.2 | ❌ 15/18 | 9.99x | 1.74x to 80.59x | 1.04x |
| Jamespath 0.5.1 | ❌ 13/18 | 8.07x | 2.74x to 26.91x | 1.38x |

Public search is faster in every mutually passing workload.
Reuse is not uniformly faster: BurtPath has lower medians in five of 15 shared workloads; Jamespath has lower medians in three of 13.
The 1.04x aggregate against BurtPath represents near parity, not a decisive reuse advantage.
No statistical significance claim is made for close medians.

BurtPath's faster reuse cases are `single_expression`, `deep_nesting_50_index`, `multi_wildcard_field`, `wildcard_with_field_match`, and `wildcard_with_field_match2`.
Jamespath's lower reuse medians occur in `single_dot_expression`, `double_dot_expression`, and `dot_no_match`.

Raw results: [all MRI providers](../../benchmark/results/comparison-mri-4.0.9.json) and [Jamespath follow-up](../../benchmark/results/comparison-jamespath-mri-4.0.9.json).
The follow-up removes a per-call adapter conditional; its Jamespath measurements supply the tables above.
The original full run remains available, including every failed case and sample.

## JRuby results

These measurements use JRuby 10.1.0.0 and Temurin Java 21.0.11.
They use the same median and geometric-mean calculation as the MRI table, with separate timing samples.

| Implementation | Correct public-search workloads | Correct reuse workloads | Public-search speedup | Reuse speedup |
| --- | ---: | ---: | ---: | ---: |
| **jmespath-ruby 0.1.0** | **✅ 18/18** | **✅ 18/18** | **1.00x** | **1.00x** |
| jmespath 1.6.2 | ✅ 18/18 | ✅ 18/18 | 7.80x | 5.24x |
| BurtPath 1.1.2 | ❌ 15/18 | ❌ 16/18 | 10.45x | 0.88x |
| Jamespath 0.5.1 | ❌ 13/18 | ❌ 13/18 | 10.23x | 0.97x |
| jmespath-jruby 1.0.0.pre0 | ❌ 0/18 | ❌ 0/18 | Unavailable | Unavailable |

Public search has lower median times in every mutually passing workload.
The range against `jmespath` is 1.42x to 87.88x.
Reuse favors BurtPath in 12 of 16 shared workloads, Jamespath in six of 13, and `jmespath` in three of 18.
This library therefore does not have a universal query-reuse advantage on JRuby.

BurtPath's filter fails during public search but passes during reuse in this execution sequence.
Its other rejected workloads are the stepped slice and Unicode function.
The Java-backed implementation fails before timing because its JAR calls a removed JRuby runtime method.
See the [complete JRuby samples](../../benchmark/results/comparison-jruby-10.1.0.0.json), including all errors.

## Beyond speed

| Capability | jmespath-ruby | jmespath | BurtPath | Jamespath | jmespath-jruby |
| --- | --- | --- | --- | --- | --- |
| Public query compilation | ✅ `compile` | ❌ Private `Runtime` | ❌ Private `Runtime` | ✅ `compile` | ✅ `compile` |
| Documented typed function registry | ✅ `Functions#with` | ❌ | ❌ | ❌ | ❌ |
| Packaged RBS signatures | ✅ | ❌ | ❌ | ❌ | ❌ |
| Pure Ruby implementation | ✅ | ✅ | ✅ | ✅ | ❌ Java extension |
| Ordinary `JMESPath.search` calls | ✅ | ✅ Original API | ✅ | ❌ Different module | ❌ Instance API |

This library's compiled expressions and function registries are immutable.
Save options at compilation, reuse queries across threads, and extend one registry without changing other callers.
Callback arguments are validated, including variadic arguments; callback errors retain their original exception and backtrace.
These guarantees are described in the [compilation](compilation.md) and [function](functions.md) guides.

Ruby input compatibility, named errors, and the positional options hash make migration from jmespath.rb practical.
The [compatibility guide](compatibility.md) lists the limits: package dependencies need updating, private internals differ, and several invalid-input behaviors are corrected.

## Method

All providers receive the same JSON-compatible input and independently recorded expected output.
The suite contains all 12 upstream benchmark cases and six supplemental cases: field lookup, projection, filter, sorting, slicing, and Unicode.
Each operation must return the expected result before warmup, after warmup, and after timing.
Rejected syntax, exceptions, and incorrect results appear as failures with no timing.

Two modes measure distinct application patterns:

- **Public search:** call the documented search API for each document. The Java-backed provider compiles on each call because it exposes no equivalent module method.
- **Reuse:** compile once or retain the provider's runtime, then query repeatedly. Parsing and setup are outside the measured loop.

The retained `JMESPath::Runtime` classes in `jmespath` and BurtPath are marked `@api private`.
They provide a stronger cached baseline but are not public compilation APIs.
This library, Jamespath, and the Java-backed implementation expose compilation APIs directly.

Measurements run on an Apple M1 Pro with arm64 macOS.
Each round starts a separate process for each provider.
Provider order and workload order rotate between rounds.
Providers run sequentially, using the same interpreter within each report, default garbage collection, and pre-parsed input.
JSON parsing, process startup, and query construction for reuse are excluded.
Results describe these workloads and runtime configurations; they do not measure application throughput or cold startup.

MRI uses 2,000 warmup calls and 20,000 measured calls in each of five rounds, with YJIT disabled.
JRuby uses 10,000 warmup calls and 10,000 measured calls in each of five rounds, with Temurin Java 21.0.11.
Its results are separate because its JVM and JIT differ from MRI.
JRuby does not provide MRI's allocated-object counter; allocation fields are null there.
These runs do not measure peak RAM.

Published gem contents are loaded directly with `-I`, without Bundler dependency activation.
This allows a source comparison on the same interpreter and JSON library.
It does not verify that each published package can be installed in a current application bundle.
In particular, BurtPath declares `json ~> 1.8`; the MRI source comparison uses JSON 3.1.0.

## Compatibility findings

Both this library and `jmespath` produce the expected results for all 18 workloads on the tested interpreters.
BurtPath fails the filter, stepped slice, and Unicode workloads on MRI.
Its filter raises a missing-constant error, the slice returns nil, and `reverse` is unknown.
Jamespath rejects the filter, sorting, stepped slice, Unicode function, and pipe workloads.
Its 13 remaining workloads return the expected results.

The Java-backed gem cannot evaluate these workloads on JRuby 10.1.0.0.
Its bundled JAR calls the removed `org.jruby.RubyObject.getNativeTypeIndex()` method.
The runner loads `jruby` before the extension to initialize its bridge; the binary incompatibility remains.
This is a failure on the tested current runtime, not a claim about historical JRuby releases.

## Reproduce

Fetch the release artifacts in a scratch directory, then unpack their sources:

```sh
gem fetch jmespath --version 1.6.2
gem unpack jmespath-1.6.2.gem
gem fetch burtpath --version 1.1.2
gem unpack burtpath-1.1.2.gem
gem fetch jamespath --version 0.5.1
gem unpack jamespath-0.5.1.gem
gem fetch jmespath-jruby --version 1.0.0.pre0 --platform java
gem unpack jmespath-jruby-1.0.0.pre0-java.gem
```

This does not install their declared dependencies.
Compare the downloaded files' SHA-256 digests with the source manifest.
Keep source directories separate because several packages provide the same require path and constants.
Create a JSON configuration with a root, provider adapter, and version for each implementation:

```json
{
  "jmespath-ruby": {"root": "/path/to/this/checkout", "provider": "jmespath", "version": "0.1.0"},
  "jmespath": {"root": "/path/to/jmespath-1.6.2", "provider": "jmespath", "version": "1.6.2"},
  "burtpath": {"root": "/path/to/burtpath-1.1.2", "provider": "jmespath", "version": "1.1.2"},
  "jamespath": {"root": "/path/to/jamespath-0.5.1", "provider": "jamespath", "version": "0.5.1"}
}
```

Run the MRI comparison:

```sh
ruby script/compare.rb --config /path/to/providers.json --iterations 20000 --warmup 2000 --rounds 5 --output /tmp/comparison.json
```

For JRuby, add the Java-backed provider to the configuration:

```json
"jmespath-jruby": {"root": "/path/to/jmespath-jruby-1.0.0.pre0-java", "provider": "jmespath-jruby", "version": "1.0.0.pre0"}
```

Run the script with the JRuby executable and a compatible `JAVA_HOME`:

```sh
jruby script/compare.rb --config /path/to/providers.json --iterations 10000 --warmup 10000 --rounds 5 --output /tmp/comparison-jruby.json
```

Keep JRuby results in a separate output file.
The runner rejects changes to library sources or workload files during measurement.
The saved MRI and JRuby reports hash files in their runtime's glob traversal order, producing different fingerprints for identical sources.
Review verified the file bytes match; the current runner explicitly sorts paths to make future fingerprints portable across runtimes.
The source manifest records the harness revision needed to reproduce each historical fingerprint.
For the earlier private-node, cache-churn, startup, and memory experiments, see [performance measurements](performance.md).
