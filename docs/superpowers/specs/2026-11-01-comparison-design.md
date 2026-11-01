# Current implementation comparison

Compare this checkout with the latest published implementations: jmespath, burtpath, jamespath, and jmespath-jruby.
Record the discovery date, versions, source hashes, and exclusions.
The empty jmespath.rb reservation and applications that merely depend on JMESPath are not implementations.

Use isolated processes, identical JSON inputs, checked results, warmup, alternating sample order, and repeated samples.
Cover the existing 18 workloads and public search and reusable-query APIs.
Keep MRI and JRuby results separate.
Report unsupported queries and incorrect results rather than counting them as speed wins.
Keep private-node measurements distinct from public APIs.
Store raw results and reproduction instructions.

Rewrite the README around measured performance, reusable immutable expressions, typed custom functions, Ruby input support, and compatibility with jmespath.rb's public search API.
Show a concise comparison table and a direct Gemfile migration example.
State dependency-name constraints and deliberate behavior corrections next to the drop-in claim.
Link full methodology and results from the README.
Do not claim universal speed or lower memory without evidence.

The selected approach is a full comparison and evidence-led README.
An MRI-only comparison would omit the JRuby implementation.
Reusing historical results would not measure the current checkout against all current releases.

Keep library behavior unchanged.
Extend benchmark tooling only as needed for the comparison.
Validate adapters and result rejection, run repository checks, and review each published claim against the evidence.
No publication, push, or release is included.
