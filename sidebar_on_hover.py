import sublime_plugin
import sublime
import subprocess
import os
import re
import json

sidebar_open = {}
active_window_id = None
proc = None
MOUSE_TRACKING_FILE_NAME_MAC = "MouseTracker"

def plugin_loaded():
  global sidebar_open
  global active_window_id

  settings = sublime.load_settings("Preferences.sublime-settings")
  plugin_disabled = settings.get("sidebar_on_hover_disabled", False)
  if plugin_disabled:
    return;

  active_window = sublime.active_window()

  sidebar_open[active_window.id()] = initial_sidebar_state()
  active_window_id = active_window.id()

  base_path = os.path.dirname(os.path.abspath(__file__))
  file_name = MOUSE_TRACKING_FILE_NAME_MAC
  left_margin = settings.get("sidebar_on_hover_left_margin", 30)
  right_margin = settings.get("sidebar_on_hover_right_margin", 250)

  sublime.set_timeout_async(
    lambda: start_mouse_tracker(base_path, file_name, left_margin, right_margin), 0
  )

def plugin_unloaded():
  global proc
  if (not proc is None):
    proc.terminate()

def initial_sidebar_state():
  sublime_path = os.path.dirname(os.path.abspath(sublime.packages_path()))
  session_file_path = os.path.join(sublime_path, "Local", "Session.sublime_session")
  with open(session_file_path) as json_file:
    json_data = json.load(json_file)
    return json_data["settings"]["new_window_settings"]["side_bar_visible"]
  return False

def start_mouse_tracker(base_path, file_name, left_margin, right_margin):
  global proc
  args = [base_path + "/" + file_name, str(left_margin), str(right_margin)]
  proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

  while (not (proc is None) and proc.poll() is None):
    try:
      data = proc.stdout.readline().decode(encoding="UTF-8")
      if (re.search("open", data)):
        set_sidebar_status(True)
      elif (re.search("close", data)):
        set_sidebar_status(False)
      elif (re.search("window_changed", data)):
        active_window_changed()
    except:
      print("Sidebar On Hover mouse tracker error...")
      return;
  print("Sidebar On Hover mouse tracker ended...")

def active_window_changed():
  global sidebar_open
  global active_window_id
  active_window = sublime.active_window()

  if (not active_window.id() in sidebar_open):
    sidebar_open[active_window.id()] = sidebar_open[active_window_id]

  active_window_id = active_window.id()

def set_sidebar_status(new_status):
  global sidebar_open
  active_window = sublime.active_window()

  if (active_window.id() in sidebar_open and new_status != sidebar_open[active_window.id()]):
    active_window.run_command("toggle_side_bar")
    sidebar_open[active_window.id()] = not sidebar_open[active_window.id()]
