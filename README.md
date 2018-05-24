# barebuild/compile

Compile binaries on-demand

## Usage

Prerequisites:

    docker pull barebuild/compile

Note: if you've made changes to the Dockerfile, you will need to rebuild it locally:

    docker build -t barebuild/compile .

This is how you test a recipe compilation:

    docker run -i --rm  -e CACHE_DIR=/app/cache -e PULL=no -v $(pwd):/app -v /var/run/docker.sock:/var/run/docker.sock barebuild/compile \
      ruby --version=2.1.3 --target=ubuntu:14.04 --prefix=/usr/local > ruby.tgz
