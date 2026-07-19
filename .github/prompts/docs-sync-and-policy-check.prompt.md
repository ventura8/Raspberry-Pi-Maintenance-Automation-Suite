______________________________________________________________________

## description: Synchronize markdown documentation with implementation and quality policies after behavior or CI changes.

Audit and synchronize documentation for recent changes.

Change context:

- {{DOC_SYNC_CONTEXT}}

Required scope:

1. README.md
1. Instructions.md
1. docs/development_standards.md
1. Any feature-specific docs under docs/

Required output:

1. Inconsistencies found.
1. Exact doc updates made.
1. Policy confirmations:

- markdown lint is mandatory
- markdown max line length is not enforced
- shell/YAML/Docker line length is 140

4. Any remaining documentation gaps.
