# Dockerfile

For building chelper and firmware

## Publishing docker file

```
docker build . -t pellcorp/k1-klipper-fw-build
docker login
docker push pellcorp/k1-klipper-fw-build
```
