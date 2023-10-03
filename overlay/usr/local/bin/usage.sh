#!/bin/sh

echo
date

echo
uname -a

echo
echo SECRET_KEY=$SECRET_KEY

echo
curl -fsSL https://raw.githubusercontent.com/dylanaraps/neofetch/7.1.0/neofetch | bash

# echo
# curl http://artscene.textfiles.com/asciiart/unicorn

echo
echo "At least one COMMAND instruction is required. See the project README for usage."

sleep infinity
