node-docker-build-action
===

Build a GasBuddy service into a docker container and deploy it to an container registry.

Uses node:18.10-bullseye for installing packages and building and then gcr.io/distroless/nodejs-debian11:18
at runtime. At time of writing, minimal service container size was about 230MB. Previous alpine based
images were 80MB, so this isn't great, but I think having a standard, modern, and secure container
like gcr distroless is probably worth the tradeoff.

Notes
==
The Dockerfile copies only selected directories, so you must be careful about where you place files that you want to be in the runtime image. The following directories are copied:

* build - Typically where built code is placed
* src - Copied for debuggability, but perhaps should be removed
* config - Configuration and keys - development.json and test.json will be removed
* migrations - Database migrations
* api - Api specification
* static - Any static files such as images, client side Javascript, etc.

And of course node_modules is built by installing production packages in the binary format of the container.

Practically, what this means is that if you have assets that you need at runtime that are not in the source directory, you should place them in config or in static.
