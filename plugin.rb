Plugin.define do
  name    "gccsense"
  version "0.1.0"
  file    "lib", "gccsense"
  object  "Redcar::GCCSense"
  dependencies "core", ">0", "project", ">0"
end