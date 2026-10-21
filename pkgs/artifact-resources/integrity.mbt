///|
pub(all) enum ChecksumAlgorithm {
  Sha1
  Sha256
  Sha512
} derive(Eq, Debug)

///|
pub fn ChecksumAlgorithm::to_string(self : ChecksumAlgorithm) -> String {
  match self {
    Sha1 => "sha1"
    Sha256 => "sha256"
    Sha512 => "sha512"
  }
}

///|
fn ChecksumAlgorithm::size(self : ChecksumAlgorithm) -> Int32 {
  match self {
    Sha1 => 20
    Sha256 => 32
    Sha512 => 64
  }
}

///|
fn ChecksumAlgorithm::rank(self : ChecksumAlgorithm) -> Int32 {
  match self {
    Sha1 => 1
    Sha256 => 2
    Sha512 => 3
  }
}

///|
/// An algorithm and digest validated together at the boundary.
pub struct Checksum {
  algorithm : ChecksumAlgorithm
  priv digest : Bytes
} derive(Eq, Debug)

///|
pub fn Checksum::parse_hex(
  algorithm : ChecksumAlgorithm,
  text : String,
) -> Checksum? {
  if text.length() != algorithm.size() * 2 {
    return None
  }
  let bytes = []
  fn digit(c : UInt16) -> Int32? {
    let n = c.to_int()
    if n >= 48 && n <= 57 {
      Some(n - 48)
    } else if n >= 65 && n <= 70 {
      Some(n - 55)
    } else if n >= 97 && n <= 102 {
      Some(n - 87)
    } else {
      None
    }
  }
  for i in 0..<algorithm.size() {
    guard digit(text[i * 2]) is Some(a) && digit(text[i * 2 + 1]) is Some(b) else {
      return None
    }
    bytes.push((a * 16 + b).to_byte())
  }
  Some({ algorithm, digest: Bytes::from_array(bytes), })
}

///|
pub fn Checksum::to_string(self : Checksum) -> String {
  self.algorithm.to_string() + ":" + @crypto.bytes_to_hex_string(self.digest)
}

///|
pub fn Checksum::matches(self : Checksum, body : Bytes) -> Bool {
  self.digest == self.algorithm.digest(body)
}

///|
fn ChecksumAlgorithm::digest(self : ChecksumAlgorithm, body : Bytes) -> Bytes {
  let actual = match self {
    Sha1 => @crypto.sha1(body)
    Sha256 => @crypto.sha256(body)
    Sha512 => @crypto.sha512(body)
  }
  Bytes::from_array(actual.iter().to_array())
}

///|
pub(all) enum NpmIntegritySource {
  Sri
  Shasum
} derive(Eq, Debug)

///|
/// Only the strongest supported SRI algorithm participates in verification.
pub struct NpmIntegrity {
  source : NpmIntegritySource
  priv checksums : Array[Checksum]
} derive(Eq, Debug)

///|
pub fn NpmIntegrity::parse_sri(text : String) -> NpmIntegrity? {
  if text.is_empty() || text.length() > 8192 {
    return None
  }
  let checksums = []
  let mut strongest = 0
  for
    token in text
    .replace_all(old="\t", new=" ")
    .replace_all(old="\r", new=" ")
    .replace_all(old="\n", new=" ")
    .split(" ") {
    if token.is_empty() {
      continue
    }
    guard token.find("-") is Some(separator) else { return None }
    let algorithm = match token[:separator] {
      "sha1" => Sha1
      "sha256" => Sha256
      "sha512" => Sha512
      _ => continue
    }
    let encoded = token[separator + 1:].to_owned()
    let digest = @base64.decode(encoded) catch { _ => return None }
    // Require canonical padded base64; the decoder also accepts some lax forms.
    if digest.length() != algorithm.size() ||
      @base64.encode(digest[:]) != encoded {
      return None
    }
    if algorithm.rank() > strongest {
      checksums.clear()
      strongest = algorithm.rank()
    }
    if algorithm.rank() == strongest {
      checksums.push(Checksum::{ algorithm, digest, })
    }
  }
  if checksums.is_empty() {
    None
  } else {
    Some({ source: Sri, checksums, })
  }
}

///|
pub fn NpmIntegrity::parse_shasum(text : String) -> NpmIntegrity? {
  Checksum::parse_hex(Sha1, text).map(checksum => {
    source: Shasum,
    checksums: [checksum],
  })
}

///|
pub fn NpmIntegrity::to_string(self : NpmIntegrity) -> String {
  let prefix = match self.source {
    Sri => "SRI "
    Shasum => "shasum "
  }
  prefix + self.checksums.map(Checksum::to_string).join(" ")
}

///|
pub fn NpmIntegrity::verify(
  self : NpmIntegrity,
  body : Bytes,
  at : Provenance,
) -> Unit raise ResourceError {
  // Every candidate has the same strongest algorithm, so hash the body once.
  let digest = self.checksums[0].algorithm.digest(body)
  if !self.checksums.any(checksum => checksum.digest == digest) {
    raise ResourceError(
      IntegrityFailure,
      at,
      "Archive does not match npm " + self.to_string(),
    )
  }
}

///|
/// Runs for fresh responses before cache publication, and for every cache hit.
pub type IntegrityVerifier = (Bytes, Provenance) -> Unit raise ResourceError
