// Centralized server-side authorization. No client-supplied role or scope is trusted.
export {currentUser,requireRole,requireVehicle,vehicleScope} from "./auth";
