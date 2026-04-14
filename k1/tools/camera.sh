#!/bin/sh

throttle_camera() {
  curl -sSfL -o /dev/null "http://127.0.0.1:8080/set_fps?fps=1"
}

restore_camera() {
  curl -sSfL -o /dev/null "http://127.0.0.1:8080/set_fps?fps=default"
}

pause_camera() {
  curl -sSfL -o /dev/null "http://127.0.0.1:8080/pause"
}

resume_camera() {
  curl -sSfL -o /dev/null "http://127.0.0.1:8080/resume"
}

if [ "$1" = "--pause" ]; then
  pause_camera
elif [ "$1" = "--resume" ]; then
  resume_camera
elif [ "$1" = "--throttle" ]; then
  throttle_camera
elif [ "$1" = "--restore" ]; then
  restore_camera
fi
