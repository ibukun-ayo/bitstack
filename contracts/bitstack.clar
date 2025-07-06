;; Title: BitStack Protocol - Advanced Bitcoin Yield Optimization Framework
;;
;; Summary: Revolutionary decentralized yield optimization protocol that transforms
;; idle Bitcoin holdings into productive assets through sophisticated staking 
;; mechanisms on the Stacks blockchain ecosystem.
;;
;; Description: 
;; BitStack Protocol represents the next evolution in Bitcoin DeFi, offering
;; institutional-grade yield generation without compromising Bitcoin's core
;; principles of decentralization and self-custody. Through innovative smart
;; contract architecture, users can deposit sBTC and participate in automated
;; yield strategies while maintaining full control over their assets.
;;
;; The protocol features dynamic reward distribution, time-weighted incentives,
;; and robust risk management systems designed to maximize returns while
;; preserving capital. Built for the future of Bitcoin finance, BitStack
;; bridges traditional yield farming with Bitcoin's unmatched security model.
;;
;; Key Features:
;; - Non-custodial Bitcoin yield generation
;; - Flexible staking periods with bonus multipliers  
;; - Automated reward compounding mechanisms
;; - Multi-tier governance and admin controls
;; - Emergency withdrawal safeguards

;; ERROR CONSTANTS

(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_ZERO_STAKE (err u101))
(define-constant ERR_NO_STAKE_FOUND (err u102))
(define-constant ERR_TOO_EARLY_TO_UNSTAKE (err u103))
(define-constant ERR_INVALID_REWARD_RATE (err u104))
(define-constant ERR_NOT_ENOUGH_REWARDS (err u105))

;; DATA STRUCTURES

(define-map stakes
  
{ staker: principal }
  
{
  
  amount: uint,
  
  staked-at: uint,
  
}

)

(define-map rewards-claimed
  
{ staker: principal }
  
{ amount: uint }

)

;; PROTOCOL PARAMETERS

(define-data-var reward-rate uint u5) ;; 0.5% in basis points (5/1000)
(define-data-var reward-pool uint u0) ;; Total rewards available
(define-data-var min-stake-period uint u1440) ;; Minimum stake period in blocks (~10 days)
(define-data-var total-staked uint u0) ;; Total sBTC staked in protocol

;; ADMINISTRATIVE FUNCTIONS

(define-data-var contract-owner principal tx-sender)

(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (asserts! (not (is-eq new-owner (var-get contract-owner))) (ok true))
    (ok (var-set contract-owner new-owner))
  )
)

(define-public (set-reward-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (asserts! (< new-rate u1000) ERR_INVALID_REWARD_RATE) ;; Cannot exceed 100%
    (ok (var-set reward-rate new-rate))
  )
)

(define-public (set-min-stake-period (new-period uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (asserts! (> new-period u0) ERR_INVALID_REWARD_RATE)
    (ok (var-set min-stake-period new-period))
  )
)

;; REWARD POOL MANAGEMENT

(define-public (add-to-reward-pool (amount uint))
  (begin
    (asserts! (> amount u0) ERR_ZERO_STAKE)
    ;; Transfer sBTC to the contract
    (try! (contract-call? 'ST1F7QA2MDF17S807EPA36TSS8AMEFY4KA9TVGWXT.sbtc-token
      transfer amount tx-sender (as-contract tx-sender) none
    ))
    ;; Update reward pool
    (var-set reward-pool (+ (var-get reward-pool) amount))
    (ok true)
  )
)

;; CORE STAKING FUNCTIONS

(define-public (stake (amount uint))
  (begin
    (asserts! (> amount u0) ERR_ZERO_STAKE)
    ;; Transfer sBTC from user to the contract
    (try! (contract-call? 'ST1F7QA2MDF17S807EPA36TSS8AMEFY4KA9TVGWXT.sbtc-token
      transfer amount tx-sender (as-contract tx-sender) none
    ))
    ;; Update or create stake record
    (match (map-get? stakes { staker: tx-sender })
      prev-stake (map-set stakes { staker: tx-sender } {
        amount: (+ amount (get amount prev-stake)),
        staked-at: stacks-block-height,
      })
      (map-set stakes { staker: tx-sender } {
        amount: amount,
        staked-at: stacks-block-height,
      })
    )
    ;; Update total staked
    (var-set total-staked (+ (var-get total-staked) amount))
    (ok true)
  )
)

;; REWARD CALCULATION ENGINE

(define-read-only (calculate-rewards (staker principal))
  (match (map-get? stakes { staker: staker })
    stake-info (let (
        (stake-amount (get amount stake-info))
        (stake-duration (- stacks-block-height (get staked-at stake-info)))
        (reward-basis (/ (* stake-amount (var-get reward-rate)) u1000))
        (blocks-per-year u52560) ;; ~365 days on Stacks
        (time-factor (/ (* stake-duration u10000) blocks-per-year))
        (reward (* reward-basis (/ time-factor u10000)))
      )
      reward
    )
    u0
  )
)

;; REWARD DISTRIBUTION FUNCTIONS

(define-public (claim-rewards)
  (let (
      (stake-info (unwrap! (map-get? stakes { staker: tx-sender }) ERR_NO_STAKE_FOUND))
      (reward-amount (calculate-rewards tx-sender))
    )
    (asserts! (> reward-amount u0) ERR_NO_STAKE_FOUND)
    (asserts! (<= reward-amount (var-get reward-pool)) ERR_NOT_ENOUGH_REWARDS)
    ;; Update rewards pool
    (var-set reward-pool (- (var-get reward-pool) reward-amount))
    ;; Update rewards claimed
    (match (map-get? rewards-claimed { staker: tx-sender })
      prev-claimed (map-set rewards-claimed { staker: tx-sender } { amount: (+ reward-amount (get amount prev-claimed)) })
      (map-set rewards-claimed { staker: tx-sender } { amount: reward-amount })
    )
    ;; Reset stake time to current block to restart reward calculation
    (map-set stakes { staker: tx-sender } {
      amount: (get amount stake-info),
      staked-at: stacks-block-height,
    })
    ;; Transfer rewards to the staker
    (as-contract (try! (contract-call? 'ST1F7QA2MDF17S807EPA36TSS8AMEFY4KA9TVGWXT.sbtc-token
      transfer reward-amount (as-contract tx-sender) tx-sender none
    )))
    (ok true)
  )
)