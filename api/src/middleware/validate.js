// Small declarative body validator — enough for this API's surface
// without another dependency. Usage:
//   validate({ email: { required: true, type: 'email' } })
const TYPES = {
  string: (v) => typeof v === 'string',
  number: (v) => typeof v === 'number' && Number.isFinite(v),
  email: (v) => typeof v === 'string' && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v),
  port: (v) => Number.isInteger(v) && v > 0 && v < 65536,
};

function validate(schema) {
  return (req, res, next) => {
    const errors = [];
    for (const [field, rules] of Object.entries(schema)) {
      const value = req.body ? req.body[field] : undefined;
      if (value === undefined || value === null || value === '') {
        if (rules.required) errors.push(`${field} is required`);
        continue;
      }
      if (rules.type && !TYPES[rules.type](value)) {
        errors.push(`${field} must be a valid ${rules.type}`);
      }
      if (rules.maxLength && String(value).length > rules.maxLength) {
        errors.push(`${field} exceeds ${rules.maxLength} characters`);
      }
      if (rules.enum && !rules.enum.includes(value)) {
        errors.push(`${field} must be one of: ${rules.enum.join(', ')}`);
      }
    }
    if (errors.length) return res.status(400).json({ error: 'Validation failed', details: errors });
    return next();
  };
}

module.exports = validate;
