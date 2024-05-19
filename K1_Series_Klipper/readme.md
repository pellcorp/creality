# Dockerfile

I have Manjaro not Ubuntu, and its easier to create a docker file which mounts the home directory for builds:

```
docker run -ti -v $PWD:$PWD pellcorp/k1-klipper-fw-build $PWD/build.sh
```

## Publishing docker file

```
docker build . -t pellcorp/k1-klipper-fw-build
docker login
docker push
```
