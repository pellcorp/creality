Building the moonraker-env.tar.gz and klippy-env with entware

# Install GCC and Python, plus a few other things

Install some basic packages:

```
/opt/bin/opkg install gcc ldd libsodium python3 python3-pip python3-dev libffi python3-uvloop libfreetype libjpeg libwebp
```

## Get the required headers

```
curl -L "https://bin.entware.net/mipselsf-k3.4/include/include.tar.gz" -o /usr/data/include.tar.gz
tar -zxvf /usr/data/include.tar.gz -C /opt/include ./jconfig.h ./jpeglib.h ./zlib.h ./freetype2 ./jmorecfg.h ./zconf.h ./ffi.h ./ffitarget.h ./webp
rm /usr/data/include.tar.gz
```

## Fix pyport missing SSIZE_MAX

I am not sure if there is a better way to get the posix limits included, but this works!

```
sed -i '/#include <limits.h>/a #include <bits/posix1_lim.h>' /opt/include/python3.11/pyport.h 
```

## Fix libffi

ld does not find libffi.so.8 for some reason

```
ln -s /opt/lib/libffi.so.8 /opt/lib/libffi.so
```

## Install virtualenv

```
/opt/bin/pip install --trusted-host pypi.python.org --trusted-host pypi.org --trusted-host=files.pythonhosted.org --no-cache-dir virtualenv
```

## Moonraker Environment

```
git clone https://github.com/Arksine/moonraker /usr/data/moonraker
/opt/bin/virtualenv -p /opt/bin/python3 --system-site-packages /usr/data/moonraker-venv
/usr/data/moonraker-venv/bin/python -m pip install --trusted-host pypi.python.org --trusted-host pypi.org --trusted-host=files.pythonhosted.org --no-cache-dir --upgrade pip
CFLAGS="-I/opt/include" /usr/data/moonraker-venv/bin/pip3 install --trusted-host pypi.python.org --trusted-host pypi.org --trusted-host=files.pythonhosted.org --require-virtualenv --no-cache-dir -r /usr/data/moonraker/scripts/moonraker-requirements.txt
/usr/data/moonraker-venv/bin/pip3 install --trusted-host pypi.python.org --trusted-host pypi.org --trusted-host=files.pythonhosted.org --require-virtualenv --no-cache-dir -r /usr/data/moonraker/scripts/moonraker-speedups.txt
cd /usr/data && tar -zcf moonraker-venv.tar.gz moonraker-venv && cd -
```

## Klippy Environment

```
curl -L "https://raw.githubusercontent.com/Klipper3d/klipper/master/scripts/klippy-requirements.txt" -o /usr/data/klippy-requirements.txt
/opt/bin/virtualenv -p /opt/bin/python3 --system-site-packages /usr/data/klippy-venv
/usr/data/klippy-venv/bin/python -m pip install --trusted-host pypi.python.org --trusted-host pypi.org --trusted-host=files.pythonhosted.org --no-cache-dir --upgrade pip
/usr/data/klippy-venv/bin/pip3 install --trusted-host pypi.python.org --trusted-host pypi.org --trusted-host=files.pythonhosted.org --require-virtualenv --no-cache-dir -r /usr/data/klippy-requirements.txt
PATH=/opt/bin /usr/data/klippy-venv/bin/pip3 install --trusted-host pypi.python.org --trusted-host pypi.org --trusted-host=files.pythonhosted.org --require-virtualenv --no-cache-dir numpy==1.25.0
cd /usr/data && tar -zcf klippy-venv.tar.gz klippy-venv && cd -
```

## Patching Pyserial serialposix.py file

We need to patch this file in both moonraker-venv and klippy-venv
