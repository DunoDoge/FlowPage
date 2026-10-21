import { BusinessError } from '@kit.BasicServicesKit';

export class PlatformFailure {
  code: number = 0;
  message: string = '';
}

// Platform callbacks throw BusinessError while catch parameters are typed as Error. This is the
// only place that narrows the type; keep new platform error handling behind this helper.
export function platformFailure(error: Object, missingCode: number = 0): PlatformFailure {
  const businessError = error as BusinessError;
  const failure = new PlatformFailure();
  failure.code = typeof businessError.code === 'number' ? businessError.code : missingCode;
  failure.message = typeof businessError.message === 'string' ? businessError.message : '';
  return failure;
}
