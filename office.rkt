#!r6rs
(import (only (racket base) require))
(require "remote.rkt")
; Everything up to this mark will be stripped and replaced
; for the embedded version.
; %%%END-OF-HEADER%%%
;----------------------------------------------------------------------------------

; mutable state
(define *room* 'lobby)
(define *info-visible* #f)
  
; Data that will be pre-cached before the first frame is rendered.
; The uri macro defines the name and adds a cache command to the init command list.
(uri WAV-ACTIVATE    "http://s3.amazonaws.com/o.oculuscdn.com/netasset/wav/ui_object_activate_01.wav")
(uri WAV-VOICE-TEST  "http://s3.amazonaws.com/o.oculuscdn.com/netasset/wav/mono_human_voice_test_01b.wav")
(uri PIC-SPLASH      "http://s3.amazonaws.com/o.oculuscdn.com/v/test/social/avatars/office_lobby.JPG")
(uri PIC-SPEAKER     "http://www.socnazlavalette.com/Speaker.jpg")
(uri PIC-TEXT        "http://t1.ftcdn.net/jpg/00/21/27/24/400_F_21272487_XfD7kRAOOJG91jvjMh0atLRgg7I4kKg7.jpg")

;-----------------
; gaze-button
;
; Draws the button and tests for gaze, returns true if it was clicked on.
;-----------------
(define (gaze-button xform pic-off pic-on pic-activate)
  (define gaze-now (gaze-on-bounds bounds3-unit xform))  
  (cmd-quad! (cond
               ((and gaze-now (held-action))   pic-activate)
               (gaze-now                       pic-on)
               (else                           pic-off))
             xform
             (if gaze-now 
                (opt-parm 1.0 1.0 0.5 1.0) 
                (opt-parm 1.0 1.0 1.0 1.0)))
  (and (pressed-action) gaze-now))
  

(define (button-xform degree-angle)
  (mat4-compose 
   (mat4-translate -0.5 -0.5 -0.5) 
   (mat4-scale/xyz 0.2 0.2 0.01) 
   (mat4-translate 0.0 2.5 -2.0) 
   (mat4-rotate-y (degrees->radians degree-angle))))
  
;-----------------
; speaker-button
; Audio annotation button.
;-----------------
(define (speaker-button degree-angle wav)
  (define bounds-trans (button-xform degree-angle))
  (cond ((gaze-button 
          bounds-trans
          PIC-SPEAKER PIC-SPEAKER PIC-SPEAKER)
         (cmd-sound! wav (mat4-origin bounds-trans)))))
  
;-----------------
; text-panel
;
; Draw a panel of text.
;-----------------
(define (count-newlines txt)
  (define (cnd index so-far)
    (cond
      ((= index -1) so-far)
      (#t (cnd (- index 1) (if (eq? (string-ref txt index) #\newline) (+ 1 so-far) so-far)))))
  (cnd (- (string-length txt) 1) 0))

; Draw a normal blended quad with the background color, then draw a non-blended quad with the
; alpha mask to enable the signed distance field TimeWarp filter.
(define (text-panel text degree-angle)
  (define lines (+ 1.0 (count-newlines text)))
  ; normal blended-edge quad that always writes alpha = 1
  (cmd-quad! "_background" 
             (mat4-compose (mat4-translate -0.5 -0.5 0.0)
                           (mat4-scale 1.4) 
                           (mat4-scale/xyz 1.35 (+ 0.1 (* 0.072 lines)) 0.0) 
                           (mat4-translate 0.0 1.6 -3.1) 
                           (mat4-rotate-y (degrees->radians degree-angle)) ) 
             (opt-parm 0.1 0.1 0.1 1.0)
             (opt-blend-ext GL_SRC_ALPHA GL_ONE_MINUS_SRC_ALPHA GL_ONE GL_ONE GL_FUNC_ADD GL_FUNC_ADD)
             'depth-mask)
  ; text will blend on top
  (cmd-text-ext! text TEXT_HORIZONTAL_CENTER TEXT_VERTICAL_CENTER
                 (mat4-compose (mat4-scale 1.4) (mat4-translate 0.0 1.6 -2.95) (mat4-rotate-y (degrees->radians degree-angle)) )))
                 
;-----------------
; text-button
;
; Text annotation button.
;-----------------
(define (text-button text degree-angle)
  (cond ((gaze-button 
          (button-xform degree-angle)
          PIC-TEXT PIC-TEXT PIC-TEXT)
         (set! *info-visible* (not *info-visible*))
         (cmd-local-sound! WAV-ACTIVATE)))
  (cond (*info-visible* (text-panel text degree-angle))))

;-----------------
; floor-tag
; Primary navigation tool.
;-----------------
(define (floor-tag title deg room)
  (define bounds-trans (mat4-compose (mat4-translate -0.5 -0.5 -0.5) 
                                     (mat4-scale/xyz 1.0 0.25 0.25) 
                                     (mat4-translate 0.0 0.75 -2.0) 
                                     (mat4-rotate-y (degrees->radians deg))))
  (define gaze-now (gaze-on-bounds bounds3-unit bounds-trans))
  
  ; Position the text
  (cmd-text! title
            (mat4-compose 
             (mat4-scale 2.0) 
             (mat4-translate 0.0 0.75 -2.0) 
             (mat4-rotate-y (degrees->radians deg)))
            (if gaze-now 
                (opt-parm 1.0 1.0 0.5 1.0) 
                (opt-parm 1.0 1.0 1.0 1.0)))
  
  ; if an input click just happened and we are gazing on it, change rooms
  (if (and (pressed-action) gaze-now)
    (begin
      (display (format "Changing to room ~a\n" room))
      (cmd-fade! -5.0) ; to black in 1.0/5.0 seconds
      (cmd-local-sound! WAV-ACTIVATE)
      (set! *room* room))
    #f)
  )

;-----------------
; init function
;
; This is optional, #f can be passed to remote at the end of the file if it isn't defined.
; launch-parms is an arbitrary s-expression that was passed to the cmd-link!
; function by another script.
;
; You can call additional cmd-init*! functions to add to the list that
; has been automatically generated by uri functions.
;-----------------
(define (init launch-parms)  
  ; This will be the splash screen
  (cmd-quad! "http://www.underconsideration.com/brandnew/archives/oculus_rift_logo_detail.png"
             (mat4-compose (mat4-scale/xyz 1.0 0.226 1.0) (mat4-translate 0.0 1.8 -2.0 ))))
  

;-----------------
; tic function
;-----------------
(define (tic)
  ; per-room actions
  (cond
    ((eq? *room* 'lobby)
     (cmd-pano! PIC-SPLASH)
     (floor-tag "John's Office" 20.0 'john-office)
     (floor-tag "Demo Room" -40.0 'demo-room)
     (text-button
"Alan Kay has famously described Lisp as
the \"Maxwell's equations of software\".
He describes the revelation he
experienced when, as a graduate student,
he was studying the LISP 1.5
Programmer's Manual and realized that
\"the half page of code on the bottom of
page 13... was Lisp in itself. These
were \"Maxwell's Equations of Software!\"
This is the whole world of programming
in a few lines that I can put my hand
over.\""
40.0)
     (speaker-button 0.0 WAV-VOICE-TEST))
                                         
    ((eq? *room* 'john-office)
     (cmd-pano! "http://s3.amazonaws.com/o.oculuscdn.com/v/test/social/avatars/office_john.JPG")
     (floor-tag "Lobby" 160.0 'lobby))
    
    ((eq? *room* 'demo-room)
     (cmd-pano! "http://s3.amazonaws.com/o.oculuscdn.com/v/test/social/avatars/office_demo.JPG")
     (floor-tag "Lobby" 45.0 'lobby)))
  )


; This connects to the HMD over TCP when run from DrRacket, and is ignored when embedded.
; Replace the IP address with the value shown on the phone when NetHmd is run.
; The init function is optional, use #f if not defined.
(remote "172.22.52.94" init tic)
 