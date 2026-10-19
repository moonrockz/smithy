///|
fn build_archive_models(path : String) -> Map[String, String] raise {
  @build.archive_models(@fs.read_file_to_bytes(path), path)
}
