# Farmer Mutual Aid Fund Feature

## Overview
Introduces an independent community support system enabling registered farmers to pool resources and provide mutual assistance during emergencies. This feature operates alongside existing subsidy tracking without dependencies.

## Technical Implementation

### Data Structures
- **mutual-aid-contributions**: Tracks individual farmer contributions (total, count, timestamps)
- **mutual-aid-requests**: Manages aid requests with voting data and status
- **mutual-aid-votes**: Records community votes on aid requests  
- **Pool variables**: Maintains global fund balance and request counter

### Key Functions

**Public Functions**:
1. `contribute-to-mutual-aid` - Deposit STX into mutual aid pool
2. `create-aid-request` - Submit assistance request with reason
3. `vote-on-aid-request` - Cast vote on pending requests
4. `finalize-aid-request` - Execute approved request and transfer funds
5. `withdraw-contribution` - Emergency withdrawal mechanism

**Read-Only Functions**:
1. `get-mutual-aid-pool-balance` - Query total pool balance
2. `get-farmer-contributions` - Retrieve contribution history
3. `get-aid-request` - Fetch request details
4. `get-aid-request-votes` - View voting statistics
5. `has-voted-on-request` - Check voting participation

### Error Handling
- Comprehensive validation with 7 new error constants
- Input sanitization for amounts and reasons
- Authorization checks for voting eligibility
- Status validation for request lifecycle

## Testing & Validation
- ✅ Contract passes `clarinet check` validation
- ✅ Comprehensive test coverage with TypeScript/Vitest
- ✅ CI/CD pipeline configured with GitHub Actions
- ✅ Clarity v3 compliant with proper error handling
- ✅ Independent feature - no cross-contract dependencies
- ✅ Line endings normalized (LF) for all files

## Integration Notes
- Seamlessly integrates with existing farmer registration system
- No modifications to existing subsidy tracking functions
- Maintains backward compatibility
- Uses consistent naming conventions and patterns

## Community Benefits
- Enables peer-to-peer farmer support
- Transparent voting mechanism
- Audit trail for all contributions and disbursements
- Emergency assistance without bureaucratic delays

## Technical Details

### New Error Constants (7 total)
```clarity
ERR_INSUFFICIENT_CONTRIBUTION (u300) - Below minimum contribution amount
ERR_REQUEST_NOT_FOUND (u301) - Invalid request ID
ERR_ALREADY_VOTED (u302) - Duplicate voting attempt
ERR_REQUEST_ALREADY_RESOLVED (u303) - Request already finalized
ERR_INSUFFICIENT_POOL_FUNDS (u304) - Not enough funds in pool
ERR_NOT_ELIGIBLE_VOTER (u305) - Non-contributor voting attempt
ERR_INVALID_REQUEST_STATUS (u306) - Invalid request state
```

### Configuration Parameters
- **Minimum contribution**: 1,000,000 STX (1 STX)
- **Minimum votes required**: 3 votes for request finalization
- **Withdrawal penalty**: 10% fee for emergency withdrawals
- **Request expiry**: No automatic expiry (manual finalization only)

### Data Flow
1. **Farmer Registration** → Existing system (no changes)
2. **Contribution Flow** → `contribute-to-mutual-aid` → Pool balance updated
3. **Request Flow** → `create-aid-request` → Community voting → `finalize-aid-request`
4. **Voting Flow** → Contributors only → Threshold-based approval
5. **Distribution Flow** → Automatic STX transfer → Balance updates

### Security Features
- Only verified farmers can contribute and request aid
- Voting restricted to contributors only
- Double-voting prevention
- Input validation for all parameters
- Block height tracking for audit trails
- Emergency withdrawal with penalty mechanism
