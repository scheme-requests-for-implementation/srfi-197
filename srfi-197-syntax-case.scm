;;; SPDX-FileCopyrightText: 2020 Adam R. Nelson <adam@nels.onl>
;;;
;;; SPDX-License-Identifier: MIT

; A syntax-case implementation of SRFI 197.
; This should be functionally equivalent to srfi-197.scm,
; but it may be easier to read and understand.

(define (gentemp) (car (generate-temporaries '(x))))

(define (id=? x y) (and (identifier? x) (free-identifier=? x y)))

(define-syntax chain
  (lambda (x)
    (syntax-case x ()
      ((_ initial-value (step ...) ...)
        #'(chain initial-value _ (... ...) (step ...) ...))
      ((_ initial-value placeholder (step ...) ...)
        #'(chain initial-value placeholder (... ...) (step ...) ...))
      ((_ initial-value placeholder ellipsis) (and (identifier? #'placeholder)
                                                   (identifier? #'ellipsis))
        #'initial-value)
      ((_ initial-value placeholder ellipsis (step ...) rest ...)
        (let loop ((vars '()) (out '()) (in #'(step ...)))
          (syntax-case in ()
            ((u …) (and (id=? #'u #'placeholder) (id=? #'… #'ellipsis))
              (let ((chain-rest-var (gentemp)))
                #`(chain (let-values ((#,(if (null? vars)
                                           chain-rest-var
                                           #`(#,@(reverse vars) . #,chain-rest-var))
                                       initial-value))
                           (apply #,@(reverse out) #,chain-rest-var))
                         placeholder
                         ellipsis
                         rest ...)))
            ((u … . _) (and (id=? #'u #'placeholder) (id=? #'… #'ellipsis))
              (syntax-violation 'chain "_ ... only allowed at end" #'(step ...)))
            ((u . step-rest) (id=? #'u #'placeholder)
              (let ((chain-var (gentemp)))
                (loop (cons chain-var vars) (cons chain-var out) #'step-rest)))
            ((… . _) (id=? #'… #'ellipsis)
              (syntax-violation 'chain "misplaced ..." #'(step ...)))
            ((x . step-rest)
              (loop vars (cons #'x out) #'step-rest))
            (()
              (with-syntax ((result (reverse out)))
                #`(chain
                    #,(cond
                        ((null? vars)
                          #'(begin initial-value result))
                        ((null? (cdr vars))
                          #`(let ((#,(car vars) initial-value)) result))
                        (else
                          #`(let-values ((#,(reverse vars) initial-value)) result)))
                    placeholder
                    ellipsis
                    rest ...)))))))))

(define-syntax chain-and
  (lambda (x)
    (syntax-case x ()
      ((_ initial-value (step ...) ...)
        #'(chain-and initial-value _ (step ...) ...))
      ((_ initial-value placeholder) (identifier? #'placeholder)
        #'initial-value)
      ((_ initial-value placeholder (step ...) rest ...)
        (let loop ((var #f) (out '()) (in #'(step ...)))
          (syntax-case in ()
            ((u . step-rest) (id=? #'u #'placeholder)
              (if var
                (syntax-violation 'chain-and "only one _ allowed per step" #'(step ...))
                (let ((chain-var (gentemp)))
                  (loop chain-var (cons chain-var out) #'step-rest))))
            ((x . step-rest)
              (loop var (cons #'x out) #'step-rest))
            (()
              (with-syntax ((result (reverse out)))
                #`(chain-and
                    #,(if var
                        #`(let ((#,var initial-value))
                            (and #,var result))
                        #'(and initial-value result))
                    placeholder
                    rest ...)))))))))

(define-syntax chain-when
  (lambda (x)
    (syntax-case x ()
      ((_ initial-value (guard? (step ...)) ...)
        #'(chain-when initial-value _ (guard? (step ...)) ...))
      ((_ initial-value placeholder) (identifier? #'placeholder)
        #'initial-value)
      ((_ initial-value placeholder (guard? (step ...)) rest ...)
        (let loop ((var #f) (out '()) (in #'(step ...)))
          (syntax-case in ()
            ((u . step-rest) (id=? #'u #'placeholder)
              (if var
                (syntax-violation 'chain-when "only one _ allowed per step" #'(step ...))
                (let ((chain-var (gentemp)))
                  (loop chain-var (cons chain-var out) #'step-rest))))
            ((x . step-rest)
              (loop var (cons #'x out) #'step-rest))
            (()
              (with-syntax ((result (reverse out)))
                #`(chain-when
                    #,(if var
                        #`(let ((#,var initial-value))
                            (if guard? result #,var))
                        #'(let ((chain-var initial-value))
                            (if guard? result chain-var)))
                    placeholder
                    rest ...)))))))))

(define-syntax chain-lambda
  (lambda (x)
    (syntax-case x ()
      ((_ (step ...) ...)
        #'(chain-lambda _ (... ...) (step ...) ...))
      ((_ placeholder (step ...) ...)
        #'(chain-lambda placeholder (... ...) (step ...) ...))
      ((_ placeholder ellipsis (first-step ...) rest ...)
        (let loop ((vars '()) (out '()) (in #'(first-step ...)))
          (syntax-case in ()
            ((u …) (and (id=? #'u #'placeholder) (id=? #'… #'ellipsis))
              (let ((chain-rest-var (gentemp)))
                #`(lambda #,(if (null? vars)
                              chain-rest-var
                              #`(#,@vars . #,chain-rest-var))
                    (chain (apply #,@(reverse out) #,chain-rest-var) placeholder ellipsis rest ...))))
            ((u … . _) (and (id=? #'u #'placeholder) (id=? #'… #'ellipsis))
              (syntax-violation 'chain-lambda "_ ... only allowed at end" #'(first-step ...)))
            ((u . step-rest) (id=? #'u #'placeholder)
              (let ((chain-var (gentemp)))
                (loop (cons chain-var vars) (cons chain-var out) #'step-rest)))
            ((… . _) (id=? #'… #'ellipsis)
              (syntax-violation 'chain-lambda "misplaced ..." #'(first-step ...)))
            ((x . step-rest)
              (loop vars (cons #'x out) #'step-rest))
            (()
              #`(lambda #,(reverse vars) (chain #,(reverse out) placeholder ellipsis rest ...)))))))))

(define-syntax nest
  (lambda (x)
    (syntax-case x ()
      ((_ last) #'last)
      ((_ (step ...) ... last) #'(nest _ (step ...) ... last))
      ((_ placeholder (extra-step ...) ... (step ...) last)
        (let loop ((arg #'last) (out '()) (in #'(step ...)))
          (syntax-case in ()
            ((u . step-rest) (id=? #'u #'placeholder)
              (if (eof-object? arg)
                (syntax-violation 'nest "only one _ allowed per step" #'(step ...))
                (loop (eof-object) (cons arg out) #'step-rest)))
            ((x . step-rest)
              (loop arg (cons #'x out) #'step-rest))
            (()
              (if (eof-object? arg)
                #`(nest placeholder (extra-step ...) ... #,(reverse out))
                (syntax-violation 'nest "step must contain _" #'(step ...)))))))
      ((_ placeholder last) #'last))))

(define-syntax nest-reverse
  (lambda (x)
    (syntax-case x ()
      ((_ first) #'first)
      ((_ first (step ...) ...) #'(nest-reverse first _ (step ...) ...))
      ((_ first placeholder (step ...) (extra-step ...) ...)
        (let loop ((arg #'first) (out '()) (in #'(step ...)))
          (syntax-case in ()
            ((u . step-rest) (id=? #'u #'placeholder)
              (if (eof-object? arg)
                (syntax-violation 'nest-reverse "only one _ allowed per step" #'(step ...))
                (loop (eof-object) (cons arg out) #'step-rest)))
            ((x . step-rest)
              (loop arg (cons #'x out) #'step-rest))
            (()
              (if (eof-object? arg)
                #`(nest-reverse #,(reverse out) placeholder (extra-step ...) ...)
                (syntax-violation 'nest-reverse "step must contain _" #'(step ...)))))))
      ((_ first placeholder) #'first))))
