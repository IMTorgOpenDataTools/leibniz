#lang racket

(provide term pattern with-signature with-sig-and-vars T)

(require "./terms.rkt"
         racket/stxparam
         (for-syntax syntax/parse
                     racket/stxparam))

(module+ test
  (require "./test-examples.rkt"
           rackunit
           racket/function))

;
; Rough validation. This needs to be improved as the
; term construction API gets clearer.
;
(define (validate signature varset value)
  (unless value
    (error "Undefined operator in term"))
  (if (allowed-term? signature value)
      value
      (error (format "illegal builtin term type ~s" (term.builtin-type value)))))

;
; Make a var (if defined in varset) or a zero-arg operator term.
; This should perhaps be in terms.rkt
;
(define (make-var-or-term signature varset name)
  (or (make-var varset name)
      (make-term signature name empty)))

;
; Basic term construction syntax
;
(begin-for-syntax
  
  (define-syntax-class (atom sig-var)
    #:description "atomic term"
    #:attributes (value)
    (pattern s:str #:with value #`(validate #,sig-var #f s))
    (pattern ((~literal quote) symbol:id)
             #:with value #`(validate #,sig-var #f (quote symbol)))
    (pattern x:number #:when (exact? (syntax-e #'x))
             #:with value #`(validate #,sig-var #f x)))

  (define-syntax-class (term sig-var)
    #:description "term"
    #:attributes (value)
    (pattern (~var a (atom sig-var)) #:with value #'a.value)
    (pattern symbol:id
             #:with value
             #`(validate #,sig-var #f
                         (make-term #,sig-var (quote symbol) empty)))
    (pattern (symbol:id (~var arg-terms (term sig-var)) ...)
             #:with value
             #`(validate #,sig-var #f
                         (make-term #,sig-var (quote symbol)
                                    (list arg-terms.value ...)))))

  (define-syntax-class (term-pattern sig-var vars-var)
    #:description "pattern"
    #:attributes (value)
    (pattern (~var a (atom sig-var)) #:with value #'a.value)
    (pattern symbol:id
             #:with value
             #`(validate #,sig-var #f
                         (make-var-or-term #,sig-var #,vars-var (quote symbol))))
    (pattern (symbol:id (~var arg-terms (term-pattern sig-var vars-var)) ...)
             #:with value
             #`(validate #,sig-var #f
                         (make-term #,sig-var (quote symbol)
                                    (list arg-terms.value ...))))))

(define-syntax (term stx)
  (syntax-parse stx
    [(_ signature:expr (~var t (term #'sig)))
     #'(let ([sig signature])
         t.value)]))

(define-syntax (pattern stx)
  (syntax-parse stx
    [(_ signature:expr varset:expr (~var p (term-pattern #'sig #'vars)))
     #'(let ([sig signature]
             [vars varset])
         p.value)]))

(module+ test
  (check-equal?  (term a-signature 2) 2)
  (check-equal?  (term a-signature an-A)
                 (make-term a-signature 'an-A empty))
  (check-equal? (term a-signature (foo a-B))
                (make-term a-signature 'foo
                           (list (make-term a-signature 'a-B empty))))
  (check-equal? (term a-signature (foo (foo a-B) a-B))
                (let* ([a-B (make-term a-signature 'a-B empty)]
                       [foo-a-B (make-term a-signature 'foo (list a-B))])
                  (make-term a-signature 'foo (list foo-a-B a-B))))
  (check-exn exn:fail? (thunk (term a-signature 'foo)))
  (check-exn exn:fail? (thunk (term a-signature "foo")))
  (check-equal? (pattern a-signature a-varset Avar)
                (make-var a-varset 'Avar))
  (check-equal? (pattern a-signature a-varset (foo Bvar))
                (make-term a-signature 'foo
                           (list (make-var a-varset 'Bvar)))))

;
; with-signature
;
(define-syntax-parameter T
  (λ (stx)
    (raise-syntax-error 'T "T keyword used outside with-signature" stx)))

(define-syntax (with-signature stx)
  (syntax-parse stx
    [(_ signature:expr body:expr ...)
     #'(let ([sig signature])
         (syntax-parameterize
           ([T (λ (stx)
                 (syntax-parse stx
                   [(_ (~var t (term #'sig)))
                    #'t.value]))])
           body ...))]))

(define-syntax (with-sig-and-vars stx)
  (syntax-parse stx
    [(_ signature:expr varset:expr body:expr ...)
     #'(let ([sig signature]
             [vars varset])
         (syntax-parameterize
           ([T (λ (stx)
                 (syntax-parse stx
                   [(_ (~var p (term-pattern #'sig #'vars)))
                    #'p.value]))])
           body ...))]))

(module+ test
  (check-equal? (term a-signature 2)
                (with-signature a-signature (T 2)))
  (check-equal? (term a-signature an-A)
                (with-signature a-signature (T an-A)))
  (with-signature a-signature
    (check-equal? (T 2) 2)
    (check-equal? (T (foo (foo a-B) a-B))
                  (term a-signature (foo (foo a-B) a-B))))
  (with-sig-and-vars a-signature a-varset
    (check-equal? (T 2) 2)
    (check-equal? (T (foo Bvar))
                  (pattern a-signature a-varset (foo Bvar)))))