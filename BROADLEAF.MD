# Update Steps

Run the following from the root of this project:
- `./gradlew clean releaseTarGz`
- `FULLY_QUALIFIED_MAIN_IMAGE_TAG=repository.broadleafcommerce.com:5001/broadleaf/kafka:3.9.1-test BUILD_AND_LOAD_LOCAL_PLATFORM_ONLY=true docker buildx bake -f docker-bake.hcl`

## Update Notes
- The `Dockerfile` at the root of this project was adapted from the `jvm` instruction set located at `docker/jvm/Dockerfile`, and was updated to pull from a local kafka build (i.e. `./core/build/distributions/`) instead of the Apache Distribution Repo and references existing scripts and resources in the `./docker` directory.
- A `docker-bake.hcl` file was added in support of a multi-platform builds