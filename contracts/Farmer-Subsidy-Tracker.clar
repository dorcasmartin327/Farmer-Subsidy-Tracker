(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_FARMER_NOT_FOUND (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_INSUFFICIENT_FUNDS (err u103))
(define-constant ERR_ALREADY_REGISTERED (err u104))
(define-constant ERR_INVALID_SUBSIDY_TYPE (err u105))
(define-constant ERR_SUBSIDY_EXPIRED (err u106))
(define-constant ERR_INVALID_FARM_SIZE (err u107))
(define-constant ERR_PAYMENT_FAILED (err u108))

(define-data-var contract-balance uint u0)
(define-data-var total-farmers uint u0)
(define-data-var total-subsidies-distributed uint u0)
(define-data-var subsidy-program-active bool true)

(define-map farmers
    { farmer-id: principal }
    {
        name: (string-ascii 50),
        farm-size: uint,
        location: (string-ascii 100),
        registration-block: uint,
        total-received: uint,
        active: bool,
        verification-status: bool,
    }
)

(define-map subsidies
    { subsidy-id: uint }
    {
        farmer-id: principal,
        subsidy-type: (string-ascii 30),
        amount: uint,
        disbursement-block: uint,
        expiry-block: uint,
        status: (string-ascii 20),
        description: (string-ascii 200),
    }
)

(define-map subsidy-types
    { type-name: (string-ascii 30) }
    {
        base-amount: uint,
        per-acre-rate: uint,
        max-amount: uint,
        active: bool,
        eligibility-requirements: (string-ascii 200),
    }
)

(define-data-var next-subsidy-id uint u1)

(define-private (is-contract-owner)
    (is-eq tx-sender CONTRACT_OWNER)
)

(define-private (validate-farm-size (size uint))
    (and (> size u0) (<= size u10000))
)

(define-private (validate-amount (amount uint))
    (and (> amount u0) (<= amount u1000000))
)

(define-private (calculate-subsidy-amount
        (farm-size uint)
        (subsidy-type (string-ascii 30))
    )
    (match (map-get? subsidy-types { type-name: subsidy-type })
        subsidy-info (let (
                (base (get base-amount subsidy-info))
                (rate (get per-acre-rate subsidy-info))
                (max-amt (get max-amount subsidy-info))
                (calculated (+ base (* farm-size rate)))
            )
            (if (<= calculated max-amt)
                calculated
                max-amt
            )
        )
        u0
    )
)

(define-public (initialize-contract)
    (begin
        (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
        (unwrap-panic (setup-default-subsidy-types))
        (ok true)
    )
)

(define-private (setup-default-subsidy-types)
    (begin
        (map-set subsidy-types { type-name: "crop-insurance" } {
            base-amount: u1000,
            per-acre-rate: u50,
            max-amount: u25000,
            active: true,
            eligibility-requirements: "Active farming operation with crop coverage",
        })
        (map-set subsidy-types { type-name: "conservation" } {
            base-amount: u2000,
            per-acre-rate: u75,
            max-amount: u50000,
            active: true,
            eligibility-requirements: "Implementation of conservation practices",
        })
        (map-set subsidy-types { type-name: "disaster-relief" } {
            base-amount: u5000,
            per-acre-rate: u100,
            max-amount: u100000,
            active: true,
            eligibility-requirements: "Documented crop loss due to natural disaster",
        })
        (ok true)
    )
)

(define-public (register-farmer
        (name (string-ascii 50))
        (farm-size uint)
        (location (string-ascii 100))
    )
    (let ((farmer-exists (is-some (map-get? farmers { farmer-id: tx-sender }))))
        (asserts! (not farmer-exists) ERR_ALREADY_REGISTERED)
        (asserts! (validate-farm-size farm-size) ERR_INVALID_FARM_SIZE)
        (asserts! (> (len name) u0) ERR_UNAUTHORIZED)
        (asserts! (> (len location) u0) ERR_UNAUTHORIZED)
        (map-set farmers { farmer-id: tx-sender } {
            name: name,
            farm-size: farm-size,
            location: location,
            registration-block: stacks-block-height,
            total-received: u0,
            active: true,
            verification-status: false,
        })
        (var-set total-farmers (+ (var-get total-farmers) u1))
        (ok true)
    )
)

(define-public (verify-farmer (farmer-id principal))
    (let ((farmer-data (unwrap! (map-get? farmers { farmer-id: farmer-id }) ERR_FARMER_NOT_FOUND)))
        (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
        (map-set farmers { farmer-id: farmer-id }
            (merge farmer-data { verification-status: true })
        )
        (ok true)
    )
)

(define-public (apply-for-subsidy
        (subsidy-type (string-ascii 30))
        (description (string-ascii 200))
    )
    (let (
            (farmer-data (unwrap! (map-get? farmers { farmer-id: tx-sender })
                ERR_FARMER_NOT_FOUND
            ))
            (subsidy-info (unwrap! (map-get? subsidy-types { type-name: subsidy-type })
                ERR_INVALID_SUBSIDY_TYPE
            ))
            (subsidy-id (var-get next-subsidy-id))
            (calculated-amount (calculate-subsidy-amount (get farm-size farmer-data) subsidy-type))
        )
        (asserts! (get active farmer-data) ERR_UNAUTHORIZED)
        (asserts! (get verification-status farmer-data) ERR_UNAUTHORIZED)
        (asserts! (get active subsidy-info) ERR_INVALID_SUBSIDY_TYPE)
        (asserts! (var-get subsidy-program-active) ERR_UNAUTHORIZED)
        (asserts! (> calculated-amount u0) ERR_INVALID_AMOUNT)
        (map-set subsidies { subsidy-id: subsidy-id } {
            farmer-id: tx-sender,
            subsidy-type: subsidy-type,
            amount: calculated-amount,
            disbursement-block: u0,
            expiry-block: (+ stacks-block-height u52560),
            status: "pending",
            description: description,
        })
        (var-set next-subsidy-id (+ subsidy-id u1))
        (ok subsidy-id)
    )
)

(define-public (approve-and-disburse-subsidy (subsidy-id uint))
    (let (
            (subsidy-data (unwrap! (map-get? subsidies { subsidy-id: subsidy-id })
                ERR_FARMER_NOT_FOUND
            ))
            (farmer-data (unwrap!
                (map-get? farmers { farmer-id: (get farmer-id subsidy-data) })
                ERR_FARMER_NOT_FOUND
            ))
            (amount (get amount subsidy-data))
        )
        (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status subsidy-data) "pending") ERR_UNAUTHORIZED)
        (asserts! (< stacks-block-height (get expiry-block subsidy-data))
            ERR_SUBSIDY_EXPIRED
        )
        (asserts! (>= (var-get contract-balance) amount) ERR_INSUFFICIENT_FUNDS)
        (try! (stx-transfer? amount tx-sender (get farmer-id subsidy-data)))
        (map-set subsidies { subsidy-id: subsidy-id }
            (merge subsidy-data {
                status: "approved",
                disbursement-block: stacks-block-height,
            })
        )
        (map-set farmers { farmer-id: (get farmer-id subsidy-data) }
            (merge farmer-data { total-received: (+ (get total-received farmer-data) amount) })
        )
        (var-set contract-balance (- (var-get contract-balance) amount))
        (var-set total-subsidies-distributed
            (+ (var-get total-subsidies-distributed) amount)
        )
        (ok true)
    )
)

(define-public (reject-subsidy
        (subsidy-id uint)
        (reason (string-ascii 200))
    )
    (let ((subsidy-data (unwrap! (map-get? subsidies { subsidy-id: subsidy-id })
            ERR_FARMER_NOT_FOUND
        )))
        (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status subsidy-data) "pending") ERR_UNAUTHORIZED)
        (map-set subsidies { subsidy-id: subsidy-id }
            (merge subsidy-data { status: "rejected" })
        )
        (ok true)
    )
)

(define-public (fund-contract (amount uint))
    (begin
        (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
        (asserts! (validate-amount amount) ERR_INVALID_AMOUNT)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (var-set contract-balance (+ (var-get contract-balance) amount))
        (ok true)
    )
)

(define-public (add-subsidy-type
        (type-name (string-ascii 30))
        (base-amount uint)
        (per-acre-rate uint)
        (max-amount uint)
        (requirements (string-ascii 200))
    )
    (begin
        (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
        (asserts! (validate-amount base-amount) ERR_INVALID_AMOUNT)
        (asserts! (validate-amount max-amount) ERR_INVALID_AMOUNT)
        (asserts! (> (len type-name) u0) ERR_UNAUTHORIZED)
        (map-set subsidy-types { type-name: type-name } {
            base-amount: base-amount,
            per-acre-rate: per-acre-rate,
            max-amount: max-amount,
            active: true,
            eligibility-requirements: requirements,
        })
        (ok true)
    )
)

(define-public (toggle-subsidy-program)
    (begin
        (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
        (var-set subsidy-program-active (not (var-get subsidy-program-active)))
        (ok (var-get subsidy-program-active))
    )
)

(define-read-only (get-farmer-info (farmer-id principal))
    (map-get? farmers { farmer-id: farmer-id })
)

(define-read-only (get-subsidy-info (subsidy-id uint))
    (map-get? subsidies { subsidy-id: subsidy-id })
)

(define-read-only (get-subsidy-type-info (type-name (string-ascii 30)))
    (map-get? subsidy-types { type-name: type-name })
)

(define-read-only (get-contract-stats)
    {
        total-farmers: (var-get total-farmers),
        total-subsidies-distributed: (var-get total-subsidies-distributed),
        contract-balance: (var-get contract-balance),
        program-active: (var-get subsidy-program-active),
        current-block: stacks-block-height,
    }
)

(define-read-only (calculate-estimated-subsidy
        (farm-size uint)
        (subsidy-type (string-ascii 30))
    )
    (calculate-subsidy-amount farm-size subsidy-type)
)

(define-read-only (get-farmer-eligibility (farmer-id principal))
    (match (map-get? farmers { farmer-id: farmer-id })
        farmer-data
        {
            registered: true,
            verified: (get verification-status farmer-data),
            active: (get active farmer-data),
            eligible: (and (get verification-status farmer-data) (get active farmer-data)),
        }
        {
            registered: false,
            verified: false,
            active: false,
            eligible: false,
        }
    )
)
