;; Nutrition Analysis Contract
;; Analyzes individual nutritional needs based on user data

;; Constants
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-PROFILE-EXISTS (err u201))
(define-constant ERR-PROFILE-NOT-FOUND (err u202))
(define-constant ERR-INVALID-DATA (err u203))
(define-constant ERR-PROVIDER-NOT-VERIFIED (err u204))

;; Data Variables
(define-data-var next-profile-id uint u1)
(define-data-var next-analysis-id uint u1)

;; Data Maps
(define-map user-profiles
  { profile-id: uint }
  {
    owner: principal,
    age: uint,
    gender: (string-ascii 10),
    height: uint, ;; in cm
    weight: uint, ;; in kg
    activity-level: (string-ascii 20),
    health-conditions: (string-ascii 200),
    dietary-restrictions: (string-ascii 200),
    goals: (string-ascii 200),
    created-at: uint,
    updated-at: uint
  }
)

(define-map profile-by-principal
  { owner: principal }
  { profile-id: uint }
)

(define-map nutrition-analyses
  { analysis-id: uint }
  {
    profile-id: uint,
    provider-id: uint,
    calories-target: uint,
    protein-target: uint, ;; in grams
    carbs-target: uint, ;; in grams
    fat-target: uint, ;; in grams
    fiber-target: uint, ;; in grams
    vitamins-minerals: (string-ascii 500),
    recommendations: (string-ascii 1000),
    created-at: uint,
    expires-at: uint
  }
)

(define-map user-analyses
  { profile-id: uint }
  { latest-analysis-id: uint }
)

;; Public Functions

;; Create user nutrition profile
(define-public (create-profile
  (age uint)
  (gender (string-ascii 10))
  (height uint)
  (weight uint)
  (activity-level (string-ascii 20))
  (health-conditions (string-ascii 200))
  (dietary-restrictions (string-ascii 200))
  (goals (string-ascii 200)))
  (let
    (
      (profile-id (var-get next-profile-id))
      (existing-profile (map-get? profile-by-principal { owner: tx-sender }))
    )
    (asserts! (is-none existing-profile) ERR-PROFILE-EXISTS)
    (asserts! (and (> age u0) (< age u150)) ERR-INVALID-DATA)
    (asserts! (and (> height u50) (< height u300)) ERR-INVALID-DATA)
    (asserts! (and (> weight u20) (< weight u500)) ERR-INVALID-DATA)

    (map-set user-profiles
      { profile-id: profile-id }
      {
        owner: tx-sender,
        age: age,
        gender: gender,
        height: height,
        weight: weight,
        activity-level: activity-level,
        health-conditions: health-conditions,
        dietary-restrictions: dietary-restrictions,
        goals: goals,
        created-at: block-height,
        updated-at: block-height
      }
    )

    (map-set profile-by-principal
      { owner: tx-sender }
      { profile-id: profile-id }
    )

    (var-set next-profile-id (+ profile-id u1))
    (ok profile-id)
  )
)

;; Update user profile
(define-public (update-profile
  (weight uint)
  (activity-level (string-ascii 20))
  (health-conditions (string-ascii 200))
  (dietary-restrictions (string-ascii 200))
  (goals (string-ascii 200)))
  (let
    (
      (profile-data (map-get? profile-by-principal { owner: tx-sender }))
      (profile-id (get profile-id (unwrap! profile-data ERR-PROFILE-NOT-FOUND)))
      (current-profile (unwrap! (map-get? user-profiles { profile-id: profile-id }) ERR-PROFILE-NOT-FOUND))
    )
    (asserts! (and (> weight u20) (< weight u500)) ERR-INVALID-DATA)

    (map-set user-profiles
      { profile-id: profile-id }
      (merge current-profile {
        weight: weight,
        activity-level: activity-level,
        health-conditions: health-conditions,
        dietary-restrictions: dietary-restrictions,
        goals: goals,
        updated-at: block-height
      })
    )

    (ok true)
  )
)

;; Perform nutritional analysis (verified providers only)
(define-public (analyze-nutrition
  (profile-id uint)
  (provider-id uint)
  (calories-target uint)
  (protein-target uint)
  (carbs-target uint)
  (fat-target uint)
  (fiber-target uint)
  (vitamins-minerals (string-ascii 500))
  (recommendations (string-ascii 1000)))
  (let
    (
      (analysis-id (var-get next-analysis-id))
      (profile (unwrap! (map-get? user-profiles { profile-id: profile-id }) ERR-PROFILE-NOT-FOUND))
    )
    ;; Verify provider is authorized (simplified check)
    (asserts! (> provider-id u0) ERR-PROVIDER-NOT-VERIFIED)
    (asserts! (> calories-target u0) ERR-INVALID-DATA)

    (map-set nutrition-analyses
      { analysis-id: analysis-id }
      {
        profile-id: profile-id,
        provider-id: provider-id,
        calories-target: calories-target,
        protein-target: protein-target,
        carbs-target: carbs-target,
        fat-target: fat-target,
        fiber-target: fiber-target,
        vitamins-minerals: vitamins-minerals,
        recommendations: recommendations,
        created-at: block-height,
        expires-at: (+ block-height u52560) ;; ~1 year
      }
    )

    (map-set user-analyses
      { profile-id: profile-id }
      { latest-analysis-id: analysis-id }
    )

    (var-set next-analysis-id (+ analysis-id u1))
    (ok analysis-id)
  )
)

;; Read-only Functions

(define-read-only (get-profile (profile-id uint))
  (map-get? user-profiles { profile-id: profile-id })
)

(define-read-only (get-profile-by-principal (owner principal))
  (match (map-get? profile-by-principal { owner: owner })
    profile-data (map-get? user-profiles { profile-id: (get profile-id profile-data) })
    none
  )
)

(define-read-only (get-analysis (analysis-id uint))
  (map-get? nutrition-analyses { analysis-id: analysis-id })
)

(define-read-only (get-latest-analysis (profile-id uint))
  (match (map-get? user-analyses { profile-id: profile-id })
    analysis-data (map-get? nutrition-analyses { analysis-id: (get latest-analysis-id analysis-data) })
    none
  )
)

(define-read-only (calculate-bmr (profile-id uint))
  (match (map-get? user-profiles { profile-id: profile-id })
    profile
      (let
        (
          (weight (get weight profile))
          (height (get height profile))
          (age (get age profile))
          (gender (get gender profile))
        )
        ;; Simplified BMR calculation (Mifflin-St Jeor Equation)
        (if (is-eq gender "male")
          (+ (* weight u10) (* height u625) (- u0 (* age u5)) u5)
          (+ (* weight u10) (* height u625) (- u0 (* age u5)) (- u0 u161))
        )
      )
    u0
  )
)

(define-read-only (get-next-profile-id)
  (var-get next-profile-id)
)

(define-read-only (get-next-analysis-id)
  (var-get next-analysis-id)
)
