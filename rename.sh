#!/bin/bash
# Replace 'henning' with your username throughout the repo
git grep -l henning | xargs sed -i 's/henning/youruser/g'
echo "Done! Remember to replace 'youruser' with your actual username."
