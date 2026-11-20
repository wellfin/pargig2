import PaymentGateway from './PaymentGateway.jsx'
import SmsGateway from './SmsGateway.jsx'
import DistanceSettings from './DistanceSettings.jsx'

/**
 * The outside services this install depends on.
 *
 * One tab rather than three, because the question people arrive with
 * is "is this thing switched on yet", and the answer is the same
 * shape for all three: a badge saying live or not, the credentials,
 * and a test that proves it rather than claiming it.
 *
 * They are kept in the order they matter on a new install. Nobody can
 * log in without SMS; money cannot move without the gateway;
 * distances already work without touching anything, which is why
 * routing is last.
 *
 * All three are superadmin-only. These are accounts that belong to
 * whoever owns the business, and the keys in them decide whether real
 * money moves and whether anyone can sign in at all — see the
 * `integrations` permission.
 */
export default function ThirdParty() {
  return (
    <div>
      <div className="panel-intro">
        <p>
          Keys and addresses for the services outside PARGIG. Each one is
          stored here rather than on the server, so switching one on does not
          need a deploy — or anybody with SSH. Secrets are encrypted and never
          shown again once saved.
        </p>
      </div>

      <SmsGateway />
      <PaymentGateway />
      <div style={{ height: 18 }} />
      <DistanceSettings />
    </div>
  )
}
