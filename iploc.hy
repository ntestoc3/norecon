(require [hy.extra.anaphoric [*]]
         [helpers [*]]
         )

(import os
        logging
        sys
        subprocess
        tempfile
        ipaddress

        [datetime [datetime]]
        [qqwry [updateQQwry QQwry]]
        [helpers [*]]
        )

(setv ip-loc (QQwry))

(defn load-qqwry
  []
  (setv data-path (os.path.join (tempfile.gettempdir) "ip_qqwry.dat"))
  (when (not (and (os.path.exists data-path)
                  (< (-> (time-modify-delta data-path)
                         (. days))
                     30)))
    (updateQQwry data-path))
  (ip-loc.load-file data-path))

(load-qqwry)

(defn get-location
  [ip]
  (->> (ip-loc.lookup ip)
       (str.join " - ")))

