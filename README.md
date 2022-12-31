# VS Code Server with Miniconda 3

A docker build of vs code server with Miniconda 3 and two factor authentication.


## Building the image

Once you have docker installed, simply build this image:

```
docker build -t code-server-miniconda3 .
```

### Set up for two factor authentication

The two factor authentication requires a key to generate time-based code in addition to a password. Both of these secrets must be present for the code-server to start. Below is an example of the `~/.config/code-server/config.yaml`
```yaml
bind-addr: 127.0.0.1:8001
auth: password
password: arandomstringof123andabc
tfa: randomshafromgenjs
cert: false
```

If you don't already have a two FA secret, do the following:

1. generate a secret two factor key using `gen.js` (you may need to install node-2fa and qr-code, see below)
```
sudo apt-get update -q && sudo apt-get install -y npm nodejs \
    && sudo apt-get clean \
    && rm -rf /var/lib/apt/lists/*
npm install node-2fa \
    && npm install qrcode
node gen.js
```

2. add the secret to `config.yaml` tfa.

### Disable two factor authentication

To disable two factor, comment out the block of code from Line 78 to 92 in `Dockerfile`, and also remove tfa from `config.yaml`.


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

### Entering password and two auth code

Since vs code server does not support two FA out of the box, the build from this repo modifies the back end of login.js to add a set of new conditions to check for two factor code using `node-2fa`. To use two FA at login, append the 6 numeric digit time-based two factor code after your password. For example, if your password is `mypassword123abc`, and at the time of login, your two factor code is `111111`, the full password that you need to enter at login would be `mypassword123abc111111`.


