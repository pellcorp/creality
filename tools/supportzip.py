#!/usr/bin/env python3

# Thanks to Chad (ChatGPT) for this code

import os
import sys
import glob
import zipfile
from pathlib import Path

def make_zip(zip_name, sources, exclude_dirs=None):
    exclude_dirs = set(exclude_dirs or [".git"])

    with zipfile.ZipFile(zip_name, 'w', zipfile.ZIP_DEFLATED, strict_timestamps=False) as zf:
        for pattern in sources:
            for path_str in glob.glob(pattern, recursive=True):
                path = Path(path_str)
                if path.is_file():
                    arcpath = str(path)
                    filename = os.path.basename(arcpath)
                    if '.log' in filename:
                        arcpath='logs/' + filename
                    zf.write(path, arcname=arcpath)
                elif path.is_dir():
                    for root, dirs, files in os.walk(path):
                        # filter excluded dirs in-place so os.walk won't descend
                        dirs[:] = [d for d in dirs if d not in exclude_dirs]

                        for f in files:
                            fpath = Path(root) / f
                            arcpath = str(fpath)
                            filename = os.path.basename(arcpath)
                            if 'printer_data/config' in arcpath:
                                arcpath='config/' + filename
                            zf.write(fpath, arcname=arcpath)


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} OUTPUT.zip SOURCES...")
        sys.exit(1)

    zip_name = sys.argv[1]
    sources = sys.argv[2:]

    make_zip(zip_name, sources)


if __name__ == "__main__":
    main()
