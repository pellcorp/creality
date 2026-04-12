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

# this resumes the camera but at the original framerate
resume_camera() {
  local fps=$1
  curl -sSfL -o /dev/null "http://127.0.0.1:8080/resume?fps=$fps"
}

if [ "$1" = "--pause" ]; then
  pause_camera
elif [ "$1" = "--resume" ]; then
  resume_camera $2
elif [ "$1" = "--throttle" ]; then
  throttle_camera
elif [ "$1" = "--restore" ]; then
  restore_camera
fi
