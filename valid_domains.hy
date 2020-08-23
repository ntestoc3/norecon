#!/usr/bin/env hy

(require [hy.extra.anaphoric [*]]
         [helpers [*]]
         )

(import os
        logging
        sys
        argparse
        time

        [retry [retry]]
        [helpers [*]]
        [async-dns [types]]
        [async-dns.resolver [ProxyResolver]]
        asyncio
        )

(defn/a resolve
  [d]
  (-> (ProxyResolver)
      (.query-safe d types.NS)
      await))

(defmain [&rest args]
  (logging.basicConfig :level logging.INFO
                       :style "{"
                       :format "{asctime} [{levelname}] {filename}({funcName})[{lineno}] {message}")

  (setv opts (parse-args [["-d" "--domain-file"
                           :nargs "?"
                           :type (argparse.FileType "r")
                           :default sys.stdin
                           :help "domain file to valid"]
                          ["-o" "--output"
                           :nargs "?"
                           :type (argparse.FileType "r")
                           :default sys.stdout
                           :help "output valid domain"]
                          ]
                         (rest args)
                         :description "valid domain resolve"))

  (logging.info "over!")
  )
