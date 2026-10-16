Feature: Release outputs
  The dist step packs the release binaries and the wasm files into dist/. Each native target has one
  archive. The archive holds one executable at its root. A checksums file lists every output.

  Scenario Outline: Name the archive and the binary of each target
    Given the target "<target>"
    Then the archive is "<archive>" and the binary is "<binary>"

    Examples:
      | target       | archive                      | binary    |
      | linux-x64    | smithy-linux-x64.tar.gz      | smithy    |
      | linux-arm64  | smithy-linux-arm64.tar.gz    | smithy    |
      | darwin-arm64 | smithy-darwin-arm64.tar.gz   | smithy    |
      | darwin-x64   | smithy-darwin-x64.tar.gz     | smithy    |
      | windows-x64  | smithy-windows-x64.zip       | smithy.exe |

  Scenario: The zig cross-build leaves out windows-x64
    Then the cross-built targets are "linux-x64,linux-arm64,darwin-arm64,darwin-x64"

  Scenario Outline: Only a Windows host builds windows-x64
    Given the OS variable "<os>"
    Then the host is Windows: "<answer>"

    Examples:
      | os         | answer |
      | Windows_NT | yes    |
      | Linux      | no     |
      |            | no     |

  Scenario: Checksums are sorted, in sha256sum format
    Given a file "b.wasm" with the content "b"
    And a file "a.zip" with the content "a"
    Then the checksums are:
      """
      ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb  a.zip
      3e23e8160039594a33894f6564e1b1348bbd7a0088d42c4acb73eeaed59c009d  b.wasm

      """

  Scenario: Missing outputs are named
    Given the expected files "smithy.wasm,smithy-gc.wasm,checksums.txt"
    And the present files "smithy.wasm,checksums.txt"
    Then the missing files are "smithy-gc.wasm"

  Scenario: The tar header has the name, the mode, the size and a checksum
    When I write a tar of the file "smithy" with the content "hello"
    Then the header field at 0 is "smithy"
    And the header field at 100 is "0000755"
    And the header field at 108 is "0000000"
    And the header field at 116 is "0000000"
    And the header field at 124 is "00000000005"
    And the header field at 136 is "00000000000"
    And the header field at 156 is "0"
    And the header field at 257 is "ustar"
    And the header field at 263 is "00"
    And the checksum field is "007203"

  Scenario: The tar is whole blocks and ends with two zero blocks
    When I write a tar of the file "smithy" with the content "hello"
    Then the tar is 2048 bytes long
    And the last 1024 bytes are zero

  Scenario Outline: The data is padded to whole blocks
    When I write a tar of the file "smithy" with <size> content bytes
    Then the tar is <length> bytes long
    And the last 1024 bytes are zero

    Examples:
      | size | length |
      | 0    | 1536   |
      | 511  | 2048   |
      | 512  | 2048   |
      | 513  | 2560   |
