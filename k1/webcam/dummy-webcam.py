#!/usr/bin/env python3

from http.server import BaseHTTPRequestHandler, HTTPServer
from sys import argv
import os 


dir_path = os.path.dirname(os.path.realpath(__file__))

class Handler(BaseHTTPRequestHandler):
    def __retrieve_image(self):
        try:
            file = open(f"{dir_path}/stopped.jpg","rb")
            file_data = file.read()
            file.close()
            return file_data
        except IOError as ioerr:
            print(str(ioerr))
            return None
        

    def do_GET(self):
        file_data = self.__retrieve_image()
        if file_data:
            file_data_len = len(file_data)
            self.send_response(200)
            self.send_header('Content-type', 'image/jpeg')
            self.send_header("Content-Length",file_data_len)
            self.end_headers()
            self.wfile.write(file_data)
        else:
            self.send_response(404)
            self.end_headers()


def run(port=8090):
    server_address = ('', port)
    httpd = HTTPServer(server_address, Handler)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    httpd.server_close()


if __name__ == '__main__':
    if len(argv) == 2:
        run(port=int(argv[1]))
    else:
        run()
