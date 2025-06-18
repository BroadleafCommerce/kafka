# Syntax reference: https://docs.docker.com/engine/reference/commandline/buildx_bake

# The fully qualified image tag (including any registry prefix) to use for the main image.
variable "FULLY_QUALIFIED_MAIN_IMAGE_TAG" {}

# Whether or not to only build images for the architecture of the machine that is running the
# build process (instead of multi-platform images). This will also force the image output type to
# 'docker', which will load the image to the local registry.
#
# Intended for local-development purposes.
variable "BUILD_AND_LOAD_LOCAL_PLATFORM_ONLY" {
  default = false
}

# Whether the system should build the more secure, but amd64 only alpine linux version
variable "LIMIT_PLATFORM" {
  default = "none"
}

# Configure the output type (ex: 'type=registry')
# Only honored when 'BUILD_AND_LOAD_LOCAL_PLATFORM_ONLY' is false.
variable "OUTPUT_TYPE" {
  default = ""
}

function "get_target_platforms" {
  params = []
  # Empty strings are filtered out, so if 'BUILD_AND_LOAD_LOCAL_PLATFORM_ONLY', then
  # platforms will be empty and only the current platform will be built.
  #
  # Note - this empty-list approach is used because specifying the built-in variable
  # 'BAKE_LOCAL_PLATFORM' didn't work. On Apple silicon, the value is resolved to 'darwin/arm64/v8',
  # and that causes errors when resolving the boot layer image. The 'normal' default-platform
  # behavior from Docker (when platform is omitted) works correctly in resolving and building
  # a 'linux/arm64' image.
  result = LIMIT_PLATFORM == "none" ? [ BUILD_AND_LOAD_LOCAL_PLATFORM_ONLY ? "" : "linux/amd64",
    BUILD_AND_LOAD_LOCAL_PLATFORM_ONLY ? "" : "linux/arm64"] : ["${LIMIT_PLATFORM}"]
}

function "get_output_config" {
  params = []
  result = [ BUILD_AND_LOAD_LOCAL_PLATFORM_ONLY ? "type=docker" : "${OUTPUT_TYPE}" ]
}

# Should contain all the targets that should be built by default
group "default" {
  targets = ["main_image"]
}

target "main_image" {
  dockerfile = "Dockerfile"
  platforms = get_target_platforms()
  tags = [ "${FULLY_QUALIFIED_MAIN_IMAGE_TAG}" ]
  output = get_output_config()
}
