#!/usr/bin/env hy

(require [hy.extra.anaphoric [*]]
         [helpers [*]]
         )

(import os
        logging
        sys
        re
        argparse
        subprocess

        [helpers [*]]
        )

(defn parse-out
  [s]
  (->> s
       (re.findall r"\[(\w+?)\]\s+(.+?)\s")
       (map second)
       list))

(defn amass
  [domain &optional [timeout 1] [out-file None] [opts []]]
  (try (setv r (subprocess.run ["amass"
                                "enum"
                                "-src"
                                #* (if out-file
                                       ["-json" out-file]
                                       [])
                                "-timeout" (str timeout)
                                #* opts
                                "-d" domain]
                               :encoding "utf-8"
                               :capture-output True))
       (if (zero? r.returncode)
           (parse-out r.stdout)
           (logging.warning "amass enum domain %s error: %s" domain r.stderr))
       (except [subprocess.TimeoutExpired]
         (logging.warn "amass enum domain %s timeout." domain))))


