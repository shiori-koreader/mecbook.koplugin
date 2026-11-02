std = "luajit"
max_line_length = false
ignore = { "212", "213" }
globals = { "G_reader_settings" }
exclude_files = { ".luarocks" }
files["spec"] = { std = "+busted" }
