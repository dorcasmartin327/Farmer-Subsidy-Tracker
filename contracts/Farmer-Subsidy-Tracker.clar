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

;; Mutual Aid Fund Error Constants
(define-constant ERR_INSUFFICIENT_CONTRIBUTION (err u300))
(define-constant ERR_REQUEST_NOT_FOUND (err u301))
(define-constant ERR_ALREADY_VOTED (err u302))
(define-constant ERR_REQUEST_ALREADY_RESOLVED (err u303))
(define-constant ERR_INSUFFICIENT_POOL_FUNDS (err u304))
(define-constant ERR_NOT_ELIGIBLE_VOTER (err u305))
(define-constant ERR_INVALID_REQUEST_STATUS (err u306))

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

(define-map farmer-subsidy-history
    {
        farmer-id: principal,
        subsidy-id: uint,
    }
    {
        block-height: uint,
        amount: uint,
        subsidy-type: (string-ascii 30),
        status: (string-ascii 20),
    }
)

;; Mutual Aid Fund Data Maps
(define-map mutual-aid-contributions
    { farmer: principal }
    {
        total-contributed: uint,
        contribution-count: uint,
        last-contribution-block: uint,
    }
)

(define-map mutual-aid-requests
    { request-id: uint }
    {
        farmer: principal,
        amount-requested: uint,
        reason: (string-utf8 500),
        votes-for: uint,
        votes-against: uint,
        status: (string-ascii 20),
        created-at-block: uint,
        resolved-at-block: uint,
    }
)

(define-map mutual-aid-votes
    { request-id: uint, voter: principal }
    {
        vote: bool,
        voted-at-block: uint,
    }
)

(define-data-var next-subsidy-id uint u1)
(define-data-var next-milestone-id uint u1)

;; Mutual Aid Fund Data Variables
(define-data-var mutual-aid-pool-balance uint u0)
(define-data-var mutual-aid-request-counter uint u0)
(define-data-var minimum-contribution uint u1000000)
(define-data-var minimum-votes-required uint u3)

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
        (map-set farmer-subsidy-history {
            farmer-id: tx-sender,
            subsidy-id: subsidy-id,
        } {
            block-height: stacks-block-height,
            amount: calculated-amount,
            subsidy-type: subsidy-type,
            status: "pending",
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
        (map-set farmer-subsidy-history {
            farmer-id: (get farmer-id subsidy-data),
            subsidy-id: subsidy-id,
        } {
            block-height: stacks-block-height,
            amount: amount,
            subsidy-type: (get subsidy-type subsidy-data),
            status: "approved",
        })
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
        (map-set farmer-subsidy-history {
            farmer-id: (get farmer-id subsidy-data),
            subsidy-id: subsidy-id,
        } {
            block-height: stacks-block-height,
            amount: (get amount subsidy-data),
            subsidy-type: (get subsidy-type subsidy-data),
            status: "rejected",
        })
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

(define-read-only (get-farmer-subsidy-history
        (farmer-id principal)
        (limit uint)
        (offset uint)
    )
    (let (
            (start-id (+ offset u1))
            (max-id (var-get next-subsidy-id))
            (calculated-end (+ start-id limit))
            (end-id (if (<= calculated-end max-id)
                calculated-end
                max-id
            ))
            (results (list))
        )
        (get results
            (fold check-and-collect
                (list
                    start-id                     (+ start-id u1)
                    (+ start-id u2)                     (+ start-id u3)
                    (+ start-id u4)
                    (+ start-id u5)                     (+ start-id u6)
                    (+ start-id u7)                     (+ start-id u8)
                    (+ start-id u9)
                ) {
                farmer-id: farmer-id,
                results: results,
                end-id: end-id,
            })
        )
    )
)

(define-private (check-and-collect
        (subsidy-id uint)
        (acc {
            farmer-id: principal,
            results: (list
                10
                (optional {
                    block-height: uint,
                    amount: uint,
                    subsidy-type: (string-ascii 30),
                    status: (string-ascii 20),
                })
            ),
            end-id: uint,
        })
    )
    (if (< subsidy-id (get end-id acc))
        (merge acc { results: (unwrap-panic (as-max-len?
            (append (get results acc)
                (map-get? farmer-subsidy-history {
                    farmer-id: (get farmer-id acc),
                    subsidy-id: subsidy-id,
                })
            )
            u10
        )) }
        )
        acc
    )
)

(define-read-only (get-farmer-subsidy-summary (farmer-id principal))
    (let ((farmer-data (map-get? farmers { farmer-id: farmer-id })))
        (match farmer-data
            farmer-info
            {
                total-received: (get total-received farmer-info),
                registration-block: (get registration-block farmer-info),
                active-status: (get active farmer-info),
                verification-status: (get verification-status farmer-info),
            }
            {
                total-received: u0,
                registration-block: u0,
                active-status: false,
                verification-status: false,
            }
        )
    )
)

(define-read-only (get-subsidy-history-entry
        (farmer-id principal)
        (subsidy-id uint)
    )
    (map-get? farmer-subsidy-history {
        farmer-id: farmer-id,
        subsidy-id: subsidy-id,
    })
)

;; =============================================================================
;; MUTUAL AID FUND FEATURE
;; =============================================================================

;; Allow farmers to contribute STX to the mutual aid pool
(define-public (contribute-to-mutual-aid (amount uint))
    (let (
        (farmer-data (unwrap! (map-get? farmers { farmer-id: tx-sender })
            ERR_FARMER_NOT_FOUND
        ))
        (current-contributions (default-to
            { total-contributed: u0, contribution-count: u0, last-contribution-block: u0 }
            (map-get? mutual-aid-contributions { farmer: tx-sender })
        ))
    )
        ;; Validate farmer eligibility and contribution amount
        (asserts! (get active farmer-data) ERR_UNAUTHORIZED)
        (asserts! (get verification-status farmer-data) ERR_UNAUTHORIZED)
        (asserts! (>= amount (var-get minimum-contribution)) ERR_INSUFFICIENT_CONTRIBUTION)
        
        ;; Transfer STX to contract
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        ;; Update contribution records
        (map-set mutual-aid-contributions { farmer: tx-sender } {
            total-contributed: (+ (get total-contributed current-contributions) amount),
            contribution-count: (+ (get contribution-count current-contributions) u1),
            last-contribution-block: stacks-block-height,
        })
        
        ;; Update pool balance
        (var-set mutual-aid-pool-balance (+ (var-get mutual-aid-pool-balance) amount))
        
        (ok true)
    )
)

;; Create an aid request for community voting
(define-public (create-aid-request (amount-requested uint) (reason (string-utf8 500)))
    (let (
        (farmer-data (unwrap! (map-get? farmers { farmer-id: tx-sender })
            ERR_FARMER_NOT_FOUND
        ))
        (request-id (var-get mutual-aid-request-counter))
    )
        ;; Validate farmer eligibility and request parameters
        (asserts! (get active farmer-data) ERR_UNAUTHORIZED)
        (asserts! (get verification-status farmer-data) ERR_UNAUTHORIZED)
        (asserts! (> amount-requested u0) ERR_INVALID_AMOUNT)
        (asserts! (> (len reason) u0) ERR_INVALID_AMOUNT)
        (asserts! (<= amount-requested (var-get mutual-aid-pool-balance)) ERR_INSUFFICIENT_POOL_FUNDS)
        
        ;; Create aid request
        (map-set mutual-aid-requests { request-id: request-id } {
            farmer: tx-sender,
            amount-requested: amount-requested,
            reason: reason,
            votes-for: u0,
            votes-against: u0,
            status: "pending",
            created-at-block: stacks-block-height,
            resolved-at-block: u0,
        })
        
        ;; Increment request counter
        (var-set mutual-aid-request-counter (+ request-id u1))
        
        (ok request-id)
    )
)

;; Vote on an aid request (only contributing farmers can vote)
(define-public (vote-on-aid-request (request-id uint) (vote bool))
    (let (
        (farmer-data (unwrap! (map-get? farmers { farmer-id: tx-sender })
            ERR_FARMER_NOT_FOUND
        ))
        (aid-request (unwrap! (map-get? mutual-aid-requests { request-id: request-id })
            ERR_REQUEST_NOT_FOUND
        ))
        (farmer-contributions (map-get? mutual-aid-contributions { farmer: tx-sender }))
        (existing-vote (map-get? mutual-aid-votes { request-id: request-id, voter: tx-sender }))
    )
        ;; Validate voter eligibility
        (asserts! (get active farmer-data) ERR_UNAUTHORIZED)
        (asserts! (get verification-status farmer-data) ERR_UNAUTHORIZED)
        (asserts! (is-some farmer-contributions) ERR_NOT_ELIGIBLE_VOTER)
        (asserts! (is-none existing-vote) ERR_ALREADY_VOTED)
        (asserts! (is-eq (get status aid-request) "pending") ERR_INVALID_REQUEST_STATUS)
        
        ;; Record vote
        (map-set mutual-aid-votes { request-id: request-id, voter: tx-sender } {
            vote: vote,
            voted-at-block: stacks-block-height,
        })
        
        ;; Update vote counts
        (if vote
            (map-set mutual-aid-requests { request-id: request-id }
                (merge aid-request { votes-for: (+ (get votes-for aid-request) u1) })
            )
            (map-set mutual-aid-requests { request-id: request-id }
                (merge aid-request { votes-against: (+ (get votes-against aid-request) u1) })
            )
        )
        
        (ok true)
    )
)

;; Finalize aid request based on community voting
(define-public (finalize-aid-request (request-id uint))
    (let (
        (aid-request (unwrap! (map-get? mutual-aid-requests { request-id: request-id })
            ERR_REQUEST_NOT_FOUND
        ))
        (farmer-data (unwrap! (map-get? farmers { farmer-id: (get farmer aid-request) })
            ERR_FARMER_NOT_FOUND
        ))
        (votes-for (get votes-for aid-request))
        (votes-against (get votes-against aid-request))
        (total-votes (+ votes-for votes-against))
        (required-votes (var-get minimum-votes-required))
        (amount (get amount-requested aid-request))
    )
        ;; Validate request status and voting requirements
        (asserts! (is-eq (get status aid-request) "pending") ERR_REQUEST_ALREADY_RESOLVED)
        (asserts! (>= total-votes required-votes) ERR_INVALID_REQUEST_STATUS)
        
        ;; Check if request is approved (more votes for than against)
        (if (> votes-for votes-against)
            (begin
                ;; Approve and disburse funds
                (asserts! (>= (var-get mutual-aid-pool-balance) amount) ERR_INSUFFICIENT_POOL_FUNDS)
                (try! (as-contract (stx-transfer? amount tx-sender (get farmer aid-request))))
                
                ;; Update pool balance
                (var-set mutual-aid-pool-balance (- (var-get mutual-aid-pool-balance) amount))
                
                ;; Update farmer's total received
                (map-set farmers { farmer-id: (get farmer aid-request) }
                    (merge farmer-data { total-received: (+ (get total-received farmer-data) amount) })
                )
                
                ;; Update request status
                (map-set mutual-aid-requests { request-id: request-id }
                    (merge aid-request {
                        status: "approved",
                        resolved-at-block: stacks-block-height,
                    })
                )
                
                (ok "approved")
            )
            (begin
                ;; Reject request
                (map-set mutual-aid-requests { request-id: request-id }
                    (merge aid-request {
                        status: "rejected",
                        resolved-at-block: stacks-block-height,
                    })
                )
                
                (ok "rejected")
            )
        )
    )
)

;; Emergency withdrawal for contributors (with 10% penalty)
(define-public (withdraw-contribution (amount uint))
    (let (
        (farmer-data (unwrap! (map-get? farmers { farmer-id: tx-sender })
            ERR_FARMER_NOT_FOUND
        ))
        (contributions (unwrap! (map-get? mutual-aid-contributions { farmer: tx-sender })
            ERR_FARMER_NOT_FOUND
        ))
        (available-amount (get total-contributed contributions))
        (penalty (/ amount u10))  ;; 10% penalty
        (withdrawal-amount (- amount penalty))
    )
        ;; Validate withdrawal
        (asserts! (get active farmer-data) ERR_UNAUTHORIZED)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (<= amount available-amount) ERR_INSUFFICIENT_CONTRIBUTION)
        (asserts! (>= (var-get mutual-aid-pool-balance) amount) ERR_INSUFFICIENT_POOL_FUNDS)
        
        ;; Transfer funds (minus penalty)
        (try! (as-contract (stx-transfer? withdrawal-amount tx-sender tx-sender)))
        
        ;; Update contribution records
        (map-set mutual-aid-contributions { farmer: tx-sender }
            (merge contributions {
                total-contributed: (- (get total-contributed contributions) amount),
                last-contribution-block: stacks-block-height,
            })
        )
        
        ;; Update pool balance (penalty remains in pool)
        (var-set mutual-aid-pool-balance (- (var-get mutual-aid-pool-balance) withdrawal-amount))
        
        (ok withdrawal-amount)
    )
)

;; =============================================================================
;; MUTUAL AID FUND READ-ONLY FUNCTIONS
;; =============================================================================

;; Get mutual aid pool balance
(define-read-only (get-mutual-aid-pool-balance)
    (var-get mutual-aid-pool-balance)
)

;; Get farmer's contribution history
(define-read-only (get-farmer-contributions (farmer principal))
    (map-get? mutual-aid-contributions { farmer: farmer })
)

;; Get aid request details
(define-read-only (get-aid-request (request-id uint))
    (map-get? mutual-aid-requests { request-id: request-id })
)

;; Get voting statistics for an aid request
(define-read-only (get-aid-request-votes (request-id uint))
    (match (map-get? mutual-aid-requests { request-id: request-id })
        request-data
        (some {
            request-id: request-id,
            votes-for: (get votes-for request-data),
            votes-against: (get votes-against request-data),
            total-votes: (+ (get votes-for request-data) (get votes-against request-data)),
            status: (get status request-data),
        })
        none
    )
)

;; Check if a farmer has voted on a specific request
(define-read-only (has-voted-on-request (request-id uint) (farmer principal))
    (is-some (map-get? mutual-aid-votes { request-id: request-id, voter: farmer }))
)

;; Get mutual aid fund statistics
(define-read-only (get-mutual-aid-stats)
    {
        pool-balance: (var-get mutual-aid-pool-balance),
        total-requests: (var-get mutual-aid-request-counter),
        minimum-contribution: (var-get minimum-contribution),
        minimum-votes-required: (var-get minimum-votes-required),
        current-block: stacks-block-height,
    }
)
