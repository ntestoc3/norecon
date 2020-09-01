
(defmacro ->2> [head &rest args]
  "Thread macro for second arg"
  (setv ret head)
  (for [node args]
    (setv ret (if (isinstance node HyExpression)
                  `(~(first node) ~(second node) ~ret ~@(drop 2 node))
                  `(~node ~ret))))
  ret)

(defmacro some-> [head &rest args]
  "Thread macro for first arg if not None"
  (setv g (gensym "some->"))
  (setv steps (->> args
                   (map (fn [step]
                          `(if (none? ~g)
                               None
                               (-> ~g ~step))))
                   list))
  (setv set-steps (map (fn [step]
                         `(setv ~g ~step))
                       (butlast steps)))
  `(do (setv ~g ~head)
       ~@set-steps
       ~(if (empty? (list steps))
            g
            (last steps))))

(defmacro some->> [head &rest args]
  "Thread macro for last arg if not None
   `unpack-iterable`无法连接起来，#*的展开比较特殊"
  (setv g (gensym "some->>"))
  (setv steps (->> args
                   (map (fn [step]
                          `(if (none? ~g)
                               None
                               (->> ~g ~step))))
                   list))
  (setv set-steps (map (fn [step]
                         `(setv ~g ~step))
                       (butlast steps)))
  `(do (setv ~g ~head)
       ~@set-steps
       ~(if (empty? (list steps))
            g
            (last steps))))

(defmacro some->2> [head &rest args]
  "Thread macro for 2nd arg if not None"
  (setv g (gensym "some->2>"))
  (setv steps (->> args
                   (map (fn [step]
                          `(if (none? ~g)
                               None
                               (->2> ~g ~step))))
                   list))
  (setv set-steps (map (fn [step]
                         `(setv ~g ~step))
                       (butlast steps)))
  `(do (setv ~g ~head)
       ~@set-steps
       ~(if (empty? (list steps))
            g
            (last steps))))

(defn get-in [m ks &optional [not-found None]]
  "深度获取dict"
  (setv r m)
  (for [k ks]
    (setv r (.get r k))
    (when (none? r)
      (return not-found)))
  r)

(defmacro timev [&rest body]
  (setv start-time (gensym "start-time"))
  (setv end-time (gensym "end-time"))
  (setv result (gensym "r"))
  `(do
     (import time)
     (setv ~start-time (time.time))
     (setv ~result ~@body)
     (setv ~end-time (time.time))
     [(- ~end-time ~start-time) ~result]))

(defmacro time [&rest body]
  (setv r (gensym "r"))
  (setv t (gensym "t"))
  `(do
     (require helpers)
     (setv [~t ~r] (helpers.timev ~@body))
     (print (.format "total run time: {:.5f} s" ~t) )
     ))

(defmacro with-exception [default-value &rest body]
  `(do
     (import logging)
     (try
       ~@body
       (except [Exception]
         (logging.exception "[Exception] use default value:%s" ~default-value)
         ~default-value))))

(require [hy.extra.anaphoric [*]])

(defmacro defmainf [args &rest body]
  "生成main函数，并在if __main__时调用"
  (setv retval (gensym)
        mainf (gensym "main_")
        restval (gensym)
        e (gensym))
  `(do
     (defn ~mainf [~@(or args `[&rest ~restval])]
       ~@body)

     (defn main []
       (import sys logging helpers [logging.handlers [RotatingFileHandler]])
       (setv main-name (try (helpers.fstem --file--)
                            (except [Exception]
                              "console")))
       (logging.basicConfig :level logging.WARNING
                            :handlers [(RotatingFileHandler
                                         :filename f"app_{main-name}.log"
                                         :maxBytes (* 5 1024 1024)
                                         :backupCount 5)
                                       (logging.StreamHandler sys.stderr)]
                            :style "{"
                            :format "{asctime} [{levelname}] {filename}({funcName})[{lineno}] {message}")
       (try
         (~mainf #* sys.argv)
         (sys.stdout.flush)
         (except [~e Exception]
           (logging.exception "main")
           (sys.stdout.flush)
           ;; 异常返回-1
           -1)))

     (when (= --name-- "__main__")
       (setv ~retval (main))
       (if (integer? ~retval)
           (sys.exit ~retval)))))

(defn set-logging-level
  [n]
  (import logging)
  (setv levels [logging.WARNING logging.INFO logging.DEBUG])
  (-> (logging.getLogger)
      (.setLevel (->> (len levels)
                      (dec)
                      (min n)
                      (of levels)))))

(defn select-keys
  [d ks]
  (->> (.items d)
       (filter #%(-> (first %1)
                     (in ks)))
       dict))

(import [multiprocessing.dummy [Pool :as ThreadPool]]
        [multiprocessing [Pool :as ProcPool]])

(defn pmap
  [f datas &optional [proc 5] [use-proc False]]
  ":proc 为进程或线程数量
   :use-proc 是否使用进程池，默认为False，使用线程池
     注意，使用进程池的话，f不能使用匿名函数"
  (with [pool (if use-proc
                  (ProcPool :processes proc)
                  (ThreadPool :processes proc))]
    (pool.map f datas)))


(defn with-retry-limit
  [f &optional
   [exceptions Exception]
   [tries -1]
   [delay 0]
   [max-delay None]
   [backoff 1]
   [jitter 0]
   [calls 15]
   [period 60]]
  (import [ratelimit [limits RateLimitException]]
          [retry [retry]])
  (-> f
      ((limits :calls calls :period period))
      ((retry exceptions
              :tries tries
              :delay delay
              :max-delay max-delay
              :backoff backoff
              :jitter jitter))))

(defn read-valid-lines
  [f]
  "按行读取文件`f`的数据，忽略空行"
  (->> (.read f)
       (.splitlines)
       (filter (comp not empty?))
       list))

(defn read-nargs-or-input-file
  [nargs input-file]
  "从narg或输入文件读取参数
   如果输入文件是stdin,并且narg参数为空，则从stdin读取输入
  "
  (if (input-file.isatty)
      (if nargs
          nargs
          (read-valid-lines input-file))
      (+ nargs
         (read-valid-lines input-file))))

(defn concat
  [&rest ls]
  (->2> (filter identity ls)
        (reduce + [])
        list))

(defn cat
  [lls]
  (concat #* lls))

(import os [datetime [datetime]])
(defn time-modify-delta
  [f]
  "文件`f`最后一次更新距离现在的时间"
  (->> (os.path.getmtime f)
       (datetime.fromtimestamp)
       (- (datetime.now))))

(defn fstem
  [f]
  "返回文件`f`不带路径和后缀的名字"
  (-> (os.path.basename f)
      (os.path.splitext)
      first))

(comment
  ;; 重试3次，每次等待5秒
  (setv pf (with-retry-limit print :tries 3 :calls 2 :delay 5))

  (pf 123)

  (pf "456")

  (pf 78))

