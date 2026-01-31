bazel --nohome_rc --nosystem_rc build --config=fuzzilli //src/workerd/server:workerd --action_env=CC=clang-19
