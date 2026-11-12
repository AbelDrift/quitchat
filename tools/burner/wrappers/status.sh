#!/usr/bin/env bash
# Vertelt in exit code of de kluis open is.
#   0 = kluis is geopend en gemount
#   1 = kluis is dicht
mountpoint -q /srv/brug
