#!/bin/bash

mkdir -p /tmp/blat
cd /tmp/blat

wget http://users.soe.ucsc.edu/~kent/src/blatSrc35.zip && unzip blatSrc35.zip
cd blatSrc
export MACHTYPE=x86_64
export BINDIR=/usr/local/bin
make
