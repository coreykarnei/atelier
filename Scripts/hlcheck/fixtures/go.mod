// Module definition for the Atelier control-plane service.
// Managed by `go mod tidy`; do not hand-edit the require blocks.
module github.com/sterlingcore/atelier-control

go 1.22.3

toolchain go1.22.5

// Direct dependencies — everything below is imported somewhere in ./cmd or ./internal.
require (
	github.com/gorilla/mux v1.8.1
	github.com/jackc/pgx/v5 v5.5.5
	github.com/rs/zerolog v1.32.0
	golang.org/x/sync v0.7.0
	google.golang.org/grpc v1.63.2
	gopkg.in/yaml.v3 v3.0.1
)

// Indirect dependencies pulled in transitively.
require (
	github.com/davecgh/go-spew v1.1.1 // indirect
	github.com/golang/protobuf v1.5.4 // indirect
	github.com/pmezard/go-difflib v1.0.0 // indirect
	github.com/stretchr/testify v1.9.0 // indirect
	golang.org/x/net v0.24.0 // indirect
	golang.org/x/sys v0.19.0 // indirect
	golang.org/x/text v0.14.0 // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20240415180920-8c6c420018be // indirect
	google.golang.org/protobuf v1.33.0 // indirect
)

// Single-line requires (older style, still legal).
require github.com/google/uuid v1.6.0
require github.com/spf13/cobra v1.8.0 // indirect
require "example.com/quoted" v1.0.0 // quoted module paths are legal

// Pseudo-versions: commit hashes and pre-release tags.
require (
	github.com/example/pending v0.0.0-20240301120000-abcdef123456
	github.com/example/rc v2.0.0-rc.1+incompatible
	github.com/example/beta/v3 v3.1.0-beta.2
)

// Local fork while an upstream fix lands.
replace github.com/rs/zerolog => ../forks/zerolog

// Pin a module to a specific version.
replace github.com/jackc/pgx/v5 v5.5.5 => github.com/jackc/pgx/v5 v5.5.4

replace (
	golang.org/x/net => golang.org/x/net v0.23.0
	github.com/example/pending v0.0.0-20240301120000-abcdef123456 => github.com/sterlingcore/pending v0.1.0
	gopkg.in/yaml.v3 => ./third_party/yaml
)

// Known-bad releases.
exclude github.com/golang/protobuf v1.5.3
exclude (
	golang.org/x/text v0.13.0
	google.golang.org/grpc v1.63.0
)

// Retracted by this module's own maintainers.
retract v0.9.0 // accidentally tagged from a broken branch
retract [v0.5.0, v0.6.2] // range with a leaked credential
retract (
	v0.1.0
	[v0.2.0, v0.3.1] // pre-stabilisation API
)
