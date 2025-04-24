; =========================
; variables
; =========================

breed [ microglia a-microglia ]          ; homeostatic microglia phenotype
breed [ m1-microglia a-m1-microglia ]    ; proinflammatory microglia phenotype

globals [
  global-glucose          ; glucose value over the entire environment, microglia will decrement this as they use glucose from the environment
  global-pH               ; pH value over the entire environment
  global-integrity        ; total percent of blood brain barrier integrity across all BBB patches
  lactate-num             ; number of patches with excess lactate
  plaque-spread-prob      ; probability that plaques will spread
  booster-frequency       ; frequency of booster dosing in hours
  plaque-eat-scalar       ; scales chance to phagocytose plaque based on exercise
  exercise-factor         ; scales plaque's spreading probability based on exercise
]

microglia-own [
  stopped?                ; boolean indicating if a microglia is stopped
  ticks-on-vessel         ; amount of time in ticks that a microglia has remained on a vessel for
  immune-tolerance?       ; boolean indicating if a microglia is in an immune tolerant state
  tolerance-timer         ; amount of time microglia have been near plaques, eventually induces tolerance
  tolerance-cooldown      ; amount of time microglia stay tolerant naturally, decrements when not near plaques
  energy?                 ; boolean indicating whether or not the microglia was successfully able to metabolise, need energy to function
]

m1-microglia-own [
  stopped?                ; boolean indicating if a microglia is stopped
  ticks-on-vessel         ; amount of time in ticks that a microglia has remained on a vessel for
  immune-tolerance?       ; boolean indicating if a microglia is in an immune tolerant state
  tolerance-timer         ; amount of time microglia have been near plaques, eventually induces tolerance
  tolerance-cooldown      ; amount of time microglia stay tolerant naturally, decrements when not near plaques
  energy?                 ; boolean indicating whether or not the microglia was successfully able to metabolise, need energy to function
]

patches-own [
  lactate?                ; boolean indicating if a patch is an originator for lactate trails
  lactate-dismantle?      ; boolean indicating if a patch is patch dismantling a trail
  lactate-val             ; amount of the lactate released as the trail
  curr-spread             ; radius of patches determining how far the trail has currently spread
  max-spread              ; max radius of patches determining how far the trail can spread
  perm-lactate?           ; boolean indicating the presence of excess lactate that cannot diffuse, remaining in the evironment
  spread-life             ; the "lifetime" or time before a trail diffuses
  integrity               ; percentage of BBB integrity, lower integrity allows larger/more molecules to pass through
  plaque-val              ; boolean representing the presence of plaques on a patch
]

; =========================
; setup and go procedures
; =========================

to setup
  clear-all
  set-default-shape m1-microglia "arrow"

  initialize-vessels    ; making the blood brain barrier (bbb) vessels

  ; randomly spawn AB plaques
  ask n-of init-plaque patches [
    set pcolor 24
    set plaque-val 1
  ]

  create-microglia init-microglia [
    set color green
    set size 2
    set stopped? false
    set ticks-on-vessel 0
    set immune-tolerance? false
    set tolerance-timer 0

    setxy random-xcor random-ycor
    while [any? other turtles-here]      ; all turtles spawn in a random location, and will
      [ setxy random-xcor random-ycor ]  ; re-randomize if the patch already contains a turtle
  ]

  ; sets up patches so microglia can then spread lactate across them
  ask patches [
    set lactate? false
    set lactate-dismantle? false
    set lactate-val 0
    set curr-spread 0
    set spread-life 10
    set max-spread 3
    update-color
  ]

  ; *** initialize chooser variables ***
  (ifelse
    metabolic-booster = "daily" [ set booster-frequency 24 ]
    metabolic-booster = "every two days" [ set booster-frequency 48 ]
    metabolic-booster = "twice per week" [ set booster-frequency 84 ]
    metabolic-booster = "weekly" [ set booster-frequency 168 ]
    [ set booster-frequency -1 ]
  )

  (ifelse
    (exercise = "high")
    [
      set plaque-eat-scalar 0.1
      set exercise-factor 0.1
    ]
    (exercise = "moderate")
    [
      set plaque-eat-scalar 0.25
      set exercise-factor 0.05
    ]
    [
      set plaque-eat-scalar 1
      set exercise-factor 0
    ]
  )

  update-spread-prob    ; calculate initial plaque spread probability

  ; *** setting monitors ***
  set global-glucose added-glucose
  set global-pH 7.3
  set global-integrity (sum [integrity] of patches) / count patches with [ integrity > 0 ] * 100

  reset-ticks
end

to go
  if ticks > 8760 [ stop ]    ; stops model after one year

  ; procedures that both microglia breeds perform
  ask ( turtle-set microglia m1-microglia )
  [
    ; all microglia move unless stopped or out of energy
    if stopped? = false and energy? = true
    [
      move
      set ticks-on-vessel 0
    ]

    ; tolerance wears off naturally when not near plaques
    if immune-tolerance? = true
    [
      set tolerance-timer 0
      if not any? neighbors with [plaque-val = 1] [set tolerance-cooldown tolerance-cooldown - 1 ]
      if tolerance-cooldown = 0 [ set immune-tolerance? false ]
    ]

    ; microglia become immune tolerant if near plaques for too long
    if tolerance-timer >= 24          ; 24 hours in day so assuming 1 tick is 1 hour
    [
      set immune-tolerance? true
      set tolerance-cooldown 96       ; stay tolerant for 4 days
    ]
  ]

  ask microglia
  [
    oxphos
    set lactate? false    ; oxphos does not create excess lactate

    ; if not near plaque, reduce tolerance timer
    if not any? neighbors with [plaque-val = 1]
    [
      if tolerance-timer > 0 [ set tolerance-timer tolerance-timer - 1 ]
    ]

    ; perform immune functions only if microglia has energy
    if energy? = true
    [
      if [ integrity ] of patch-here > 0 [survey-and-fortify]    ; if on a blood vessel, build up its integrity

      if stopped? [ set ticks-on-vessel ticks-on-vessel + 1 ]    ; stop microglia on vessel for a limited period of time (ticks)

      ; become proinflammatory if adjacent to plaque
      if any? neighbors with [plaque-val = 1]
      [
        if not immune-tolerance? [ set breed m1-microglia ]
      ]

      ; become proinflammatory if fortifying bbb for too long
      if ticks-on-vessel = 40
      [
        if not immune-tolerance? [ set breed m1-microglia ]
        set ticks-on-vessel 0
        set stopped? false
      ]
    ]
  ]

  ask m1-microglia
  [
    glycolysis

    ; if not near plaque, reduce tolerance timer
    if not any? neighbors with [plaque-val = 1]
    [
      if tolerance-timer > 0 [ set tolerance-timer tolerance-timer - 1 ]
    ]

    ; perform immune functions only if microglia has energy
    if energy? = true
    [
      set lactate? true    ; successful glycolysis creates excess lactate

      ; when on a plaque, increment tolerance timer and attempt to phagocytose plaque
      if [ plaque-val ] of patch-here = 1
        [
          set tolerance-timer tolerance-timer + 1
          phagocytose-plaque
        ]

      if [ integrity ] of patch-here > 0 [phagocytose-bbb]       ; if on a blood vessel, degrade its integrity

      if stopped? [ set ticks-on-vessel ticks-on-vessel + 1 ]    ; stop microglia on vessel for a limited period of time (ticks)

      ; if stopped on vessel for too long remain activated but begin moving
      if ticks-on-vessel = 40
      [
        set ticks-on-vessel 0
        set stopped? false
      ]
    ]
  ]

  ask patches with [ lactate? and (curr-spread < max-spread) ] [ spread-trail ]  ; if there is a lactate present and the lactate has not fully spread, spread the trail
  ask patches with [ lactate-dismantle? ] [set spread-life spread-life - 1]      ; if the trail is dismantling, the lactate is diffusing
  ask patches with [ spread-life <= 0] [ reset-trail ]                           ; reset patches where the lactate trail has fully diffused

  ; plaques will spread periodically with variable probability
  if (ticks mod 500 = 0)
  [
    ask patches with [ plaque-val = 1 ]
    [
      ask neighbors4 [diffuse-plaque]
    ]
  ]

  ; if exercise is high or moderate, the integrity of the bbb will increase periodically
  if ((ticks mod 300 = 0) and (exercise = "high"))
  [
    ask patches with [ integrity != 0 and integrity < 1 ]
    [
      set integrity integrity + 0.01
      if integrity > 1 [ set integrity 1 ]
    ]
  ]

  if ((ticks mod 500 = 0) and (exercise = "moderate"))
  [
    ask patches with [ integrity != 0 and integrity < 1 ]
    [
      set integrity integrity + 0.01
      if integrity > 1 [ set integrity 1 ]
    ]
  ]

  ask patches [ update-color ]

  set global-pH 7.3                                         ; resets the global-pH value to account for factors maintaing normal ph in brain
  set lactate-num (count patches with [ pcolor = white ])   ; counts the number of white patches which represents excess lactate
  set global-pH global-pH - (lactate-num * 0.02)            ; decreases the pH based on the amount of excess lactate
  update-spread-prob                                        ; updates plaque spread probability based on ph and exercise

  set global-glucose global-glucose + added-glucose

  ; apply metabolic booster depending on chosen booster frequency
  if booster-frequency != -1 and ticks mod booster-frequency = 0
  [
    ask ( turtle-set microglia m1-microglia)
    [
      set immune-tolerance? false
      set tolerance-timer 0
    ]
  ]

  set global-integrity (sum [integrity] of patches) / count patches with [ integrity > 0 ] * 100    ; update global bbb integrity monitor

  tick
end

; ======================
; turtle procedures
; ======================

; initialization procedure for blood vessels
to initialize-vessels
  ; create a turtle for each blood vessel
  crt init-vessels [

    let side random 4    ; pick one of the four sides

    ; depending on the side, set its position randomly along that side
    (ifelse
    side = 0 [
      setxy (min-pxcor + 1) random-ycor
    ]
    side = 1 [
      setxy (max-pxcor - 1) random-ycor
    ]
    side = 2 [
      setxy random-xcor (min-pycor + 1)
    ]
    side = 3 [
      setxy random-xcor (max-pycor - 1)
    ])

    face patch 0 0
  ]

  while [any? turtles]
  [
    ask turtles [
      ask patch-here [ set integrity (random-float 0.5) + 0.5 ]    ; set the integrity of the patch being visited between 0.5 and 1

      ; random walk
      rt random 30
      lt random 30
      fd 1

      ; delete turtle if it reaches the edge of the screen
      let patch-x [pxcor] of patch-here
      let patch-y [pycor] of patch-here
      if patch-x >= max-pxcor or patch-x <= min-pxcor or patch-y >= max-pycor or patch-y <= min-pycor [
        die
      ]
    ]
  ]
end

; microglia and m1-microglia move procedure
to move
    rt random 50
    lt random 50
    fd 1
end

; ======================
; microglia procedures
; ======================

; microglia fortify integrity of bbb
to survey-and-fortify
  set stopped? true    ; when microglia encounter a bbb patch, they stop

  ; build up a vessels integrity with variable probability
  if random-float 1 < fortify-probability
  [
    ask patch-here [ set integrity integrity + 0.01 ]
    if integrity > 1 [ set integrity 1 ]
  ]
end

; oxidative phosphorylation metabolism
to oxphos
  (ifelse global-glucose >= 42
    [
      set global-glucose global-glucose - 42
      set energy? true
    ]
    [ set energy? false ]    ; if not enough glucose, microglia doesn't have energy to function
  )
end

; ======================
; m1-microglia procedures
; ======================

; m1-microglia degrade integrity of bbb
to phagocytose-bbb
  set stopped? true    ; when m1-microglia encounter a bbb patch, they stop

  ; degrade a vessels integrity with variable probability
  if random-float 1 < eat-probability
  [
    ask patch-here [ set integrity integrity - 0.01 ]
  ]

  ; if they completely degrade a vessel, deactivate and move again
  if [ integrity ] of patch-here <= 0
  [
    set breed microglia
    set stopped? false
    ask patch-here [ set integrity 0 ]
  ]
end

; m1-microglia attempt to clear plaques
to phagocytose-plaque
  set stopped? true

  ; clear plaque with variable probability scaled by the presence of exercise
  if (random-float 1 * plaque-eat-scalar < eat-probability)
    [
      set breed microglia    ; switch back to homeostatic if successful
      set stopped? false
      ask patch-here
      [
        set plaque-val 0
      ]
    ]

end

; glycolysis metabolism
to glycolysis
  (ifelse global-glucose >= 420    ; glycolysis uses 10x more glucose than oxphos
    [
      set global-glucose global-glucose - 420
      set energy? true
    ]
    [ set energy? false ]    ; if not enough glucose, m1-microglia doesn't have energy to function
  )
end

; m1-microglia secrete lactate as a product of glycolysis metabolism
to spread-trail
  ; produces lactate within the current spread radius
  ask patches in-radius curr-spread [
    set lactate-val lactate-val + 1
    update-color
    set lactate-dismantle? true
  ]
  set curr-spread curr-spread + 1

  ; excess lactate is left in the environment with variable probability
  if random-float 1 <  lactate-probability [
    lactate-perm-trail
  ]
end

; ======================
; patch procedures
; ======================

; excess lactate becomes a semi-permenant lactate deposit
to lactate-perm-trail
  set pcolor 9.9
  set lactate-dismantle? false
  set lactate? false
  set perm-lactate? true
end

; fully resets patches whose lactate have completely diffused
to reset-trail
  set lactate-val lactate-val - 1
  if lactate-val = 0
    [
      set spread-life 10
      set lactate-dismantle? false
      set curr-spread 0
      set max-spread 3
      set lactate? false
      set perm-lactate? false
    ]
  update-color
end

; plaques spread with a probability based on environmental factors
to diffuse-plaque
  if random-float 1 < plaque-spread-prob
  [
    set plaque-val 1    ; gives inflammation to patches within the current spreading radius
    set pcolor 24
  ]
end

; recalculate plaque spread probability based on lactate in the environment
to update-spread-prob
  (ifelse
    (global-pH > 7) [ set plaque-spread-prob 0.2 ]
    (global-pH < 6.2) [ set plaque-spread-prob 0.9 ]
    [set plaque-spread-prob ((-1.048951) * (global-pH ^ 3) + 20.92657 * (global-pH ^ 2)) - (139.60227 * global-pH) + 311.95485]
  )

  ; if exercising, subtract constant factor decreasing plaque spread probability
  set plaque-spread-prob plaque-spread-prob - exercise-factor

end

; update colors of patches every tick
to update-color
  (ifelse
    (perm-lactate? = true) [set pcolor white]                                                         ; lactate deposits are white
    (lactate-val != 0 and lactate-dismantle? = true) [set pcolor scale-color sky lactate-val 0 10]    ; lactate trails are blue
    (plaque-val != 0) [set pcolor 24]                                                                 ; plaques are orange
    [set pcolor scale-color red integrity 0 3]                                                        ; bbb vessels are red
  )
end
@#$#@#$#@
GRAPHICS-WINDOW
210
10
647
448
-1
-1
13.0
1
10
1
1
1
0
1
1
1
-16
16
-16
16
0
0
1
ticks
30.0

BUTTON
13
28
76
61
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
86
28
149
61
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
13
76
185
109
init-microglia
init-microglia
0
50
10.0
1
1
NIL
HORIZONTAL

SLIDER
13
227
185
260
lactate-probability
lactate-probability
0
1
0.2
0.01
1
NIL
HORIZONTAL

SLIDER
13
151
185
184
init-vessels
init-vessels
0
50
5.0
1
1
NIL
HORIZONTAL

SLIDER
13
189
185
222
eat-probability
eat-probability
0
1
0.1
0.01
1
NIL
HORIZONTAL

SLIDER
13
265
185
298
fortify-probability
fortify-probability
0
1
0.1
0.01
1
NIL
HORIZONTAL

SLIDER
13
113
185
146
init-plaque
init-plaque
0
50
3.0
1
1
NIL
HORIZONTAL

MONITOR
219
458
336
503
NIL
global-glucose
17
1
11

MONITOR
372
459
489
504
NIL
global-pH
3
1
11

SLIDER
13
303
185
336
added-glucose
added-glucose
500
8000
2400.0
100
1
NIL
HORIZONTAL

CHOOSER
13
342
186
387
metabolic-booster
metabolic-booster
"daily" "every two days" "twice per week" "weekly" "none"
4

CHOOSER
13
394
186
439
exercise
exercise
"none" "moderate" "high"
1

MONITOR
522
459
639
504
global-integrity (%)
global-integrity
2
1
11

@#$#@#$#@
## WHAT IS IT?

This model simulates microglia, a type of immune cell in the central nervous system (CNS), and their interactions within a 2-dimensional slice of the hippocampus. It builds on a previous model that simulated microglia and their interaction with neurons and cytokines, a kind of signaling protein. This version of the model is focused on microglia metabolism and glucose consumption in the context of Alzheimer’s Disease (AD).

Microglia are responsible for phagocytosing (eating) cellular debris and fighting infections in the CNS. They can also modulate blood brain barrier (BBB) permeability, which regulates the flow of molecules between the bloodstream and the brain. To perform their immune tasks, microglia utilize glucose as their primary energy source. However, impaired microglia metabolism can cause harm to the CNS. This includes causing excess lactate in the brain, more acidic pH, greater levels of Aβ plaques, and a "leaky" BBB with lower barrier integrity. These are all symptoms and hallmarks of AD, which currently has no cure or definitive cause. 

However, recent research has shown that exercise and metabolic boosters are potential treatments to AD. Exercise regimens can reduce the growth rate of Aβ plaques, while metabolic boosters such as GLP-1 receptor agonists can help rescue immune tolerant microglia and restore their immune functions. Therefore, this model helps simulate the effects of impaired microglia metabolism on the progression of AD disease, as well as how these potential therapies may rescue microglial function by acting on metabolic pathways.

## HOW IT WORKS

This simulation relies on microglia agents and patch variables representing Aβ plaques, the BBB, and lactate accumulation. The primary outcomes of this model are the effects of microglia metabolism on Aβ plaque accumulation, brain pH, and BBB permeability. One tick of the simulation represents a time step of one hour, and simulations last 8,760 ticks (one year).

### Microglia

This model includes two agent breeds, homeostatic and proinflammatory (M1) microglia. Homeostatic microglia are represented by an arrowhead shape, while M1 microglia are represented by a directional arrow shape. Both breeds accomplish their defined tasks through pseudo-random movement, and an agent can switch between these breeds depending on specific environmental cues.

Homeostatic microglia undergo oxidative phosphorylation (OXPHOS) to metabolize glucose, allowing them to generate ATP (energy). These microglia can also strengthen the BBB by increasing their INTEGRITY value. However, strengthening the BBB for too long can cause microglia to become proinflammatory, switching to the M1 breed. Homeostatic microglia can also become proinflammatory when adjacent to an Aβ plaque.

M1 microglia undergo glycolysis to metabolize glucose, which is a faster way to generate ATP to supply their immune response. This comes at the cost of greater glucose consumption (around 10 times more than OXPHOS)  and lactate generation. Excessive lactate can cause a pH imbalance within the hippocampus, contributing to greater levels of Aβ plaques. M1 microglia can phagocytose (clear) Aβ plaques, upon which they switch back to the homeostatic breed.

### Blood Brain Barrier

As part of SETUP, the BBB is initialized with the INITIALIZE-VESSELS procedure. Temporary agents are created and randomized on one of the sides of the environment. These agents will then randomly move throughout the environment, setting the INTEGRITY of the patches they encounter by some positive amount. Patches with a nonzero INTEGRITY value will be a shade of red, with stronger colors representing greater integrity. The initializing agents die once reaching an edge of the environment, creating a trail of patches representing a blood vessel. The number of these agents can be adjusted through the INIT-VESSELS slider.

Homeostatic microglia that encounter a blood vessel patch will strengthen BBB integrity. However, fortifying for too long can cause homeostatic microglia to switch to the proinflammatory M1 breed. M1 microglia instead decrease the INTEGRITY value of the BBB, representing an increase in permeability.

### Glucose Levels

Every tick, microglia use some amount of glucose from the GLOBAL-GLUCOSE value. The amount of glucose used varies depending on the chosen metabolic pathway. Glycolysis, used by proinflammatory microglia, uses 10 times more glucose compared to OXPHOS, used by homeostatic microglia. If microglia cannot obtain enough glucose from the environment, they will stop in place and be unable to perform any immune responses.

The amount of glucose entering the system is influenced by ADDED-GLUCOSE, a variable indicating the amount of glucose entering the system per tick. The total glucose in the environment is represented by GLOBAL-GLUCOSE, and its initial value upon setup is equal to ADDED-GLUCOSE.

### Lactate and pH

When microglia are proinflammatory, the use of glycolysis causes an excess of lactate to be secreted into the extracellular space. This is visualized through the light blue trails emitted from M1 microglia. Under typical circumstances, excess lactate can be used by the environment, such as by neurons. However, too much lactate can cause semi-permanent lactate deposits (white) to appear. These deposits cause the pH of the environment to decrease, which can increase the probability that Aβ plaques spread. The chance that a blue lactate patch becomes a lactate deposit is influenced through the LACTATE-PROBABILITY slider.

To visualize the spread of lactate, patches can emit a light blue trail that dissipates after a certain amount of time. For more information on the procedures related to lactate spread trails, see our work on the cytokine and inflammation procedures found in [our previous model.](https://ccl.northwestern.edu/netlogo/models/community/Microglia%20Model)

### Aβ Plaques

The number of initial patches with an Aβ plaque (orange) can be adjusted with the INIT-PLAQUE slider. At regular intervals, existing Aβ plaques will attempt to spread to other patches, representing the progression of AD. The chance that spreading succeeds relies on the PLAQUE-SPREAD-PROB variable. This variable is inversely related to the current pH. With exercise, PLAQUE-SPREAD-PROB is reduced by a constant amount. The greater the exercise intensity, the lower the spread probability.

M1 microglia are responsible for phagocytosing Aβ plaques that they encounter. The chance that a proinflammatory microglia succeeds in phagocytosing plaque is dependent on the EAT-PROBABILITY slider and PLAQUE-EAT-SCALAR variable, which is based on the selected exercise amount. If successful, the microglia becomes homeostatic and plaque will be removed from the patch.

### Exercise

The EXERCISE chooser represents the level of daily exercise, which influences the spread of Aβ plaques. When set to “none”, the probability of plaques spreading relies only on the current pH of the system, with lower pH causing a higher chance of spreading. With exercise, chances of plaque spreading decreases while their chances of removal by microglia increases. Additionally, exercise also periodically increases the INTEGRITY of BBB patches. Higher exercise intensity will result in a greater effect.

### Immune Tolerance

If proinflammatory microglia are adjacent to Aβ plaques for an extended period of time (one day), they become immune tolerant. When they switch back to homeostatic, these microglia cannot become proinflammatory for a temporary period of time. The time in which a microglia agent is tolerant increases as they continue to stay adjacent to plaques. 

Metabolic booster effects are set with the METABOLIC-BOOSTER chooser. Choices represent common dose frequencies, such as “daily” or “weekly”. Given one tick representing one hour, the chosen boosting frequency determines the interval between doses. Whenever a metabolic booster is applied, all currently tolerant microglia will cease being tolerant.

## HOW TO USE IT

The Interface tab includes sliders and switches that modify the simulation. Below is a description of these variables:

* INIT-MICROGLIA: The number of microglia that are initialized in the model.

* INIT-PLAQUE: The number of initial patches that contain an Aβ plaque.

* INIT-VESSELS: The number of blood vessels created by the INITIALIZE-VESSELS procedure during SETUP.

* EAT-PROBABILITY: The probability that a proinflammatory microglia successfully phagocytoses an Aβ plaque.

* LACTATE-PROBABILITY: The probability that part of a lactate trail becomes a lactate deposit.

* FORTIFY-PROBABILITY: The probability that a homeostatic microglia successfully increases the INTEGRITY of the current vessel patch.

* ADDED-GLUCOSE: The amount of glucose that is added per tick. This also determines the starting GLOBAL-GLUCOSE value.

* METABOLIC-BOOSTER: The interval in which a metabolic booster is applied to the system, rescuing immune tolerant microglia.

* EXERCISE: The level of exercise to represent within the system, influencing the spread of Aβ plaques.

## THINGS TO NOTICE

Some things to notice when the simulation starts are:

* Aβ plaques can spread exponentially over time.

* When Aβ plaques comprise a large portion of the environment, microglia stay immune tolerant for longer periods of time.

* The number of lactate deposits accumulates the longer the model runs.

* Blood vessels fade to black as their INTEGRITY level decreases.

## THINGS TO TRY

Try varying the level of EXERCISE in the model without any metabolic boosters, then observe the spread of Aβ plaques. Next, try varying the levels of METABOLIC-BOOSTER without any exercise. Which treatments seem more effective in clearing plaques? Which treatments affect BBB permeability more? Does combining the effects of exercise and metabolic boosters provide an even better result?

Try changing INIT-MICROGLIA and ADDED-GLUCOSE, then watch the levels of GLOBAL-GLUCOSE on the monitor. What happens when microglia use glucose faster than it is replenished? Does having too much glucose in the system affect the microglias’ behavior? Additionally, try to find values for INIT-MICROGLIA and ADDED-GLUCOSE that strike a balance between glucose consumption and replenishment.

To see all of the model’s functions working together, try the following starting values:

* INIT-MICROGLIA: 10

* INIT-PLAQUE: 3

* INIT-VESSELS: 5

* EAT-PROBABILITY: 0.10

* LACTATE-PROBABILITY: 0.20

* FORTIFY-PROBABILITY: 0.10

* ADDED-GLUCOSE: 2400

* METABOLIC-BOOSTER: none

* EXERCISE: moderate

## EXTENDING THE MODEL

The CNS is a multi-faceted system with a myriad of different cells, pathways, and interactions. Our model is a simplification of the interaction between microglia, their metabolism, and AD. Ways to extend this model include:

* Astrocytes, another cell in the CNS, play a key role in modulating BBB permeability and protecting the brain from injuries and infections. These cells can respond to chemical signals sent by microglia and neurons, as well as send their own chemical signals. Modeling the interactions between astrocytes and microglia may help with understanding the role of these cells in AD contexts.

* Angiogenesis is the process by which new blood vessels are formed from existing vessels. Excess lactate and exercise can stimulate angiogenesis, which can improve brain function. However, defective blood vessels may form around Aβ plaques, disrupting the blood brain barrier. Developing this model to include angiogenesis can help better model how the BBB is affected by AD progression.

* Neurons, astrocytes, and microglia all use glucose as a source of energy. This model currently only takes into account microglia metabolism using glucose. However, some evidence points to microglia and neurons being able to use lactate as an emergency energy source. Future models can take glucose consumption by other cell types into consideration, alongside alternative energy sources.

* The timing in which metabolic boosters are started for people susceptible to/have AD may affect whether the treatment is successful. The model currently only supports the interval between booster timing rather than when this treatment was started in terms of current AD progression. Future models can take into account different AD stages and how the effects of metabolic boosters vary depending on which stage patients began receiving them.

## RELATED MODELS

Our previous microglia model is posted here: [Microglia Model](https://ccl.northwestern.edu/netlogo/models/community/Microglia%20Model)

## CREDITS AND REFERENCES

This project was supported by NSF grant 2245839 from the Mathematical Biology program. We are deeply grateful for this support.

We would also like to thank Amanda Case and Emmanuel Mezzulo for their work on our previous model, on which this one builds from.

For more information about microglia, see our publication in Spora: A Journal of Biomathematics: [https://ir.library.illinoisstate.edu/spora/vol11/iss1/3/](https://ir.library.illinoisstate.edu/spora/vol11/iss1/3/).

## HOW TO CITE

If you mention this model or the NetLogo software in a publication, we ask that you include the citations below.

For the model itself:

Penland, A.\*, Ty, C.\*, Gerving, J., Mendoza-Ceja, M., Pratt, M., & Larripa, K. (2025). Microglia Metabolism Model. Cal Poly Humboldt, Arcata, CA.

\* These authors contributed equally to this work.

Please cite the NetLogo software as:

Wilensky, U. (1999). NetLogo. http://ccl.northwestern.edu/netlogo/. Center for Connected Learning and Computer-Based Modeling, Northwestern University, Evanston, IL.
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
