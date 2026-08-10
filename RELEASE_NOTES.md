**Fixed**

- With two Latin layouts installed, the wrong one could be used to read what you
  typed. Typing `yvf` on the Czech layout gave `нма` instead of `яма`, because
  both layouts can produce those letters and the app picked between them
  arbitrarily. It now uses the keyboard you're actually typing on.
