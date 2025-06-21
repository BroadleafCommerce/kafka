# Update Steps

- Update `build.gradle` and `dependencies.gradle` for correct remediation versions.
- `./gradlew test` (Full test suite takes 4 hours!!)
- At the time of this writing, `SocketServerTest` consistently fails - even without any changes. As a result, ignoring this particular test result.
- `./gradlew clean releaseTarGz`
- For local testing: `FULLY_QUALIFIED_MAIN_IMAGE_TAG=repository.broadleafcommerce.com:5001/broadleaf/kafka:3.9.1-alpine-3.2.1-jre-21.0.7_6-r1 BUILD_AND_LOAD_LOCAL_PLATFORM_ONLY=true docker buildx bake -f docker-bake.hcl`
- For release: `FULLY_QUALIFIED_MAIN_IMAGE_TAG=repository.broadleafcommerce.com:5001/broadleaf/kafka:3.9.1-alpine-3.2.1-jre-21.0.7_6-r1 docker buildx bake --builder blc-devops-multiplatform-builder -f docker-bake.hcl --push` (Increment the `r1` to a higher value if only changing java or os deps without changing app, jre, or os versions).

## Update Notes
- The `Dockerfile` at the root of this project was adapted from the `jvm` instruction set located at `docker/jvm/Dockerfile`, and was updated to pull from a local kafka build (i.e. `./core/build/distributions/`) instead of the Apache Distribution Repo and references existing scripts and resources in the `./docker` directory.
- A `docker-bake.hcl` file was added in support of a multi-platform builds