# Shared PostgressOps install path defaults.
# Override per host: export POSTGRESSOPS_HOME=/your/path
# Override repo:       export POSTGRESSOPS_REPO=https://github.com/you/postgressops.git

: "${POSTGRESSOPS_HOME:=/opt/postgressops}"
: "${POSTGRESSOPS_REPO:=https://github.com/Makmillerme/postgressops.git}"

export POSTGRESSOPS_HOME POSTGRESSOPS_REPO
