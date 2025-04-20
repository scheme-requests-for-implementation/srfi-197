;;; SPDX-FileCopyrightText: 2020 Adam R. Nelson <adam@nels.onl>
;;;
;;; SPDX-License-Identifier: MIT

(define (syntax-violation who msg irr)
  (error msg (cons who irr)))

(include "./srfi-197-syntax-case.scm")
(include "./test.scm")
