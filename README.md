# VS Code Server with Miniconda 3

## Building the image

Once you have docker installed, simply build this image:

```
docker build -t code-server-miniconda3 .
```

## Using the image

Starting the server using the same config as the base code-server:

```
docker run -it --rm --name code-server -p 127.0.0.1:8080:8080 \
  -v "$HOME/.config:/home/coder/.config" \
  -v "$PWD:/home/coder/project" \
  -u "$(id -u):$(id -g)" \
  -e "DOCKER_USER=$USER" \
  code-server-miniconda3:latest
```