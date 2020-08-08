


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


(defmacro bench [&rest body]
  (import time)
  (setv start-time (gensym "start-time"))
  (setv end-time (gensym "end-time"))
  `(do (setv ~start-time (time.time))
       ~@body
       (setv ~end-time (time.time))
       (print (.format "total run time: {:.5f} s" (- ~end-time ~start-time)))))

(defmacro with-exception [&rest body]
  `(do
     (import logging)
     (try
       ~@body
       (except [e Exception]
         (logging.error "exception: %s" e)))))

(require [hy.extra.anaphoric [*]])

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



