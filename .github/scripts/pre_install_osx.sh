#!/bin/sh

sudo spctl --master-disable
brew install --cask $FUSE_PKG
sudo spctl --status
exit 0
